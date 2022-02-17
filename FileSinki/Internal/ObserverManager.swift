//
//  ObserverManager.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 7/05/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation
import CloudKit

internal final class ObserverManager {

    private let cloudKitManager: CloudKitManager
    private let localDB: LocalDatabase

    init(cloudKitManager: CloudKitManager, localDB: LocalDatabase) {
        self.cloudKitManager = cloudKitManager
        self.localDB = localDB

        FileSinki.reachability.addPermanentRetryOperation( {
            self.didBecomeActive()
        })
    }

    func addObserver(_ observer: AnyObject,
                     path: String,
                     root: FileManager.SearchPathDirectory,
                     onChange: @escaping FileSinki.GenericChanged) {
        let fileURL = URL(path: path, root: root)
        guard let cloudPath = fileURL.cloudPath(for: root) else {
            DebugAssert(false, "Failed to generate a valid cloudpath for \(fileURL)")
            return
        }
        let record = ObserverRecord(observer: observer,
                                    cloudPath: cloudPath,
                                    root: root,
                                    onChange: onChange)
        addObserver(record)
    }

    func addObserver<T>(_ observer: AnyObject,
                        fileSyncableType: T.Type,
                        path: String,
                        root: FileManager.SearchPathDirectory,
                        onChange: @escaping FileSinki.ChangeItem<T>.Changed) where T: FileSyncable {
        let fileURL = URL(path: path, root: root)
        guard let cloudPath = fileURL.cloudPath(for: root) else {
            DebugAssert(false, "Failed to generate a valid cloudpath for \(fileURL)")
            return
        }
        let record = TypedObserverRecord(observer: observer,
                                         fileSyncableType: fileSyncableType,
                                         cloudPath: cloudPath,
                                         root: root,
                                         onChange: onChange)
        addObserver(record)
    }

    private var observers = [ObserverRecord]()
    private func addObserver(_ observer: ObserverRecord) {
        runOnMain {
            self.observers.append(observer)
            self.checkForRemoteChanges(observer, specificRecord: nil)
            self.addRemoteSubscription(observer)
        }
    }

    private func removeDeadObservers() {
        observers.removeAll { $0.observer == nil }
    }

    private func checkForRemoteChanges(_ observer: ObserverRecord, specificRecord: String?) {
        removeDeadObservers()

        guard observers.count > 0 else { return }

        observer.fetchPotentialRecordsMatching(recordID: specificRecord ?? observer.recordID,
                                               cloudKitManager: cloudKitManager) { [weak observer] recordList in
            guard let observer = observer else { return }
            self.receivedFileList(recordList, for: observer)
        }
    }

    private func receivedFileList(_ list: [CloudKitManager.FetchAllResult],
                                  for observer: ObserverRecord) {
        let localKnownFiles = localDB.knownFilesMatching(recordID: observer.recordID)

        var changedList = list

        for localFile in localKnownFiles {
            let wildCardMatch = observer.recordID.last == "/"

            changedList.removeAll { remote in
                if wildCardMatch {
                    return remote.recordID == localFile.recordID &&
                            remote.version == localFile.version
                } else {
                    // need an exact match
                    if remote.recordID != localFile.recordID {
                        return true
                    }
                    return remote.version == localFile.version
                }
            }
        }

        guard changedList.count > 0 else {
            removeDeadObservers()
            return
        }
        if observer.observer != nil {
            observer.processRemoteChangedList(changedList)
        }

        removeDeadObservers()
    }

    // MARK: - Remote Notifications

    func receivedNotification(_ notificationPayload: [AnyHashable : Any]) {
        guard let note = CKQueryNotification(fromRemoteNotificationDictionary: notificationPayload) else {
            return
        }

        if let recordZone = note.recordID?.zoneID,
            recordZone.zoneName != CloudKitManager.privateZoneId.zoneName {
            return  // notification was for somebody else
        }
        let recordID: String? = note.recordID?.recordName
        let cloudPath: String? = note.recordFields?[CloudKitManager.RecordKey.path.rawValue] as? String
        // none of these fields are guaranteed, we'll have to make do
        let observers = observersMatching(recordID: recordID,
                                          cloudPath: cloudPath)
        for observer in observers {
            self.checkForRemoteChanges(observer, specificRecord: recordID)
        }
    }

    func observersMatching(recordID: String?, cloudPath: String?) -> [ObserverRecord] {
        return observers.filter { record -> Bool in
            let wildCardMatch = record.recordID.last == "/"

            if wildCardMatch {
                if let recordID = recordID {
                    return recordID.contains(record.recordID)  // best check
                } else if let cloudPath = cloudPath {
                    return cloudPath.contains(record.recordID.recordIDWithFileSinkiPrefixRemoved())  // not so good, but not terrible.
                } else {
                    return true // can't do anything but check all observers
                }
            } else {
                if let recordID = recordID {
                    return record.recordID == recordID  // best check
                } else if let cloudPath = cloudPath {
                    return record.recordID.recordIDWithFileSinkiPrefixRemoved() == cloudPath  // not so good, but not terrible.
                } else {
                    return true // can't do anything but check all observers
                }
            }
        }
    }

    func addRemoteSubscription(_ observer: ObserverRecord) {
        cloudKitManager.addNotificationSubscription(recordID: observer.recordID)
    }

    // MARK: - App Resuming and Network Connectivity

    func didBecomeActive() {
        runOnMain {
            for observer in self.observers {
                self.checkForRemoteChanges(observer, specificRecord: nil)
            }
        }
    }

}

// MARK: - Observer Records

internal class ObserverRecord {

    weak var observer: AnyObject?
    let recordID: String
    let onChange: FileSinki.GenericChanged?

    init(observer: AnyObject,
         cloudPath: String,
         root: FileManager.SearchPathDirectory,
         onChange: FileSinki.GenericChanged?) {
        self.observer = observer
        self.recordID = cloudPath.toRecordID(root: root)
        self.onChange = onChange
    }

    func fetchPotentialRecordsMatching(recordID: String,
                                       cloudKitManager: CloudKitManager,
                                       then: @escaping (_ list: [CloudKitManager.FetchAllResult]) -> ()) {
        cloudKitManager.fetchAllRecordsContaining(recordID: recordID) { matchingRecords in
            then(matchingRecords)
        }
    }

    func processRemoteChangedList(_ changedList: [CloudKitManager.FetchAllResult]) {
        var changedItems = [FileSinki.ChangeItemGeneric]()
        for item in changedList {
            guard let url = item.recordID.recordIDToLocalURL() else { continue }
            let path = item.recordID.recordIDWithFileSinkiPrefixRemoved()
            changedItems.append(FileSinki.ChangeItemGeneric(localURL: url, path: path))
        }
        self.onChange?(changedItems)
    }

}

internal final class TypedObserverRecord<T: FileSyncable>: ObserverRecord {

    let type: T.Type
    let onTypedChange: FileSinki.ChangeItem<T>.Changed

    init(observer: AnyObject,
         fileSyncableType: T.Type,
         cloudPath: String,
         root: FileManager.SearchPathDirectory,
         onChange: @escaping FileSinki.ChangeItem<T>.Changed) {
        self.type = fileSyncableType
        self.onTypedChange = onChange
        super.init(observer: observer,
                   cloudPath: cloudPath,
                   root: root,
                   onChange: nil)
    }

    override func fetchPotentialRecordsMatching(recordID: String, cloudKitManager: CloudKitManager, then: @escaping ([CloudKitManager.FetchAllResult]) -> ()) {
        cloudKitManager.fetchAllRecordsContaining(recordID: recordID,
                                                  type: type) { matchingRecords in
            then(matchingRecords)
        }
    }

    override func processRemoteChangedList(_ changedList: [CloudKitManager.FetchAllResult]) {
        for item in changedList {
            guard let url = item.recordID.recordIDToLocalURL() else { continue }
            let path = item.recordID.recordIDWithFileSinkiPrefixRemoved()

            FileSinki.load(type,
                           fromPath: url.path) { [weak self] loaded, wasRemote in
                guard wasRemote,
                    let self = self,
                    let loaded = loaded else {
                    return
                }
                let changedItem = FileSinki.ChangeItem<T>(item: loaded,
                                                          localURL: url,
                                                          path: path)
                self.onTypedChange(changedItem)
            }
        }
    }

}
