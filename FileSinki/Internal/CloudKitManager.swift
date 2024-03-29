//
//  CloudKitManager.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 15/04/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation
import CloudKit
import Compression

internal final class CloudKitManager: NSObject {

    enum RecordKey: String {
       case recordID
       case path
       case data
       case asset
       case deleted
       case type
    }

    internal static let privateZoneName = "FileSinki"
    internal static let privateZoneId = CKRecordZone.ID(zoneName: privateZoneName,
                                                        ownerName: CKCurrentUserDefaultName)

    private static let fileSinkiRecordType = "FileSinki"

    private let privateDatabase: CKDatabase

    private let localDB: LocalDatabase

    // anything less than .userInitiated is likely to never complete. Especially on OSX.
    private let qualityOfService: QualityOfService = .userInitiated

    // MARK: - Init

    init(cloudKitContainer: String, localDB: LocalDatabase) {
        privateDatabase = CKContainer(identifier: cloudKitContainer).privateCloudDatabase
        self.localDB = localDB
    }

    // MARK: - Public Interface

    func saveDataToCloud<T>(fileURL: URL,
                            searchPathDirectory: FileManager.SearchPathDirectory,
                            originalItem: T,
                            data: Data,
                            compression: compression_algorithm?,
                            finalVersion: @escaping (_ item: T) -> ()) where T: FileSyncable {
        guard let cloudPath = fileURL.cloudPath(for: searchPathDirectory) else {
            DebugAssert(false, "Failed to get cloud path for \(fileURL)")
            return
        }

        let recordID = cloudPath.toRecordID(root: searchPathDirectory)
        self.localDB.addPendingSaveRecordFor(recordID: recordID, type: T.self, compressed: compression != nil)

        ifHaveZone {
            self.saveOrDeleteRecord(recordID: recordID,
                                    cloudPath: cloudPath,
                                    searchPathDirectory: searchPathDirectory,
                                    originalItem: originalItem,
                                    data: data,
                                    delete: false,
                                    compression: compression,
                                    finalVersion: finalVersion)
        }
    }

    func deleteDataInCloud<T>(fileURL: URL,
                              searchPathDirectory: FileManager.SearchPathDirectory,
                              originalItem: T,
                              data: Data,
                              compression: compression_algorithm?) where T: FileSyncable {
        guard let cloudPath = fileURL.cloudPath(for: searchPathDirectory) else {
            DebugAssert(false, "Failed to get cloud path for \(fileURL)")
            return
        }

        let recordID = cloudPath.toRecordID(root: searchPathDirectory)
        self.localDB.addPendingSaveRecordFor(recordID: recordID, type: T.self, compressed: compression != nil)

        ifHaveZone {
            self.saveOrDeleteRecord(recordID: cloudPath.toRecordID(root: searchPathDirectory),
                                    cloudPath: cloudPath,
                                    searchPathDirectory: searchPathDirectory,
                                    originalItem: originalItem,
                                    data: data,
                                    delete: true,
                                    compression: compression,
                                    finalVersion: nil)
        }
    }

    typealias ReceivedDataClosure = ((_ path: String,
                                      _ decompressedData: Data?,
                                      _ remoteIsDeleted: Bool) -> ())

    func loadDataFromCloud<T>(fileURL: URL,
                           type: T.Type,
                           searchPathDirectory: FileManager.SearchPathDirectory,
                           compression: compression_algorithm?,
                           onReceive: @escaping ReceivedDataClosure) where T: FileSyncable {
        guard let cloudPath = fileURL.cloudPath(for: searchPathDirectory) else {
            DebugAssert(false, "Failed to get cloud path for \(fileURL)")
            return
        }

        let recordID = cloudPath.toRecordID(root: searchPathDirectory)
        self.localDB.addLocalKnownFileFor(recordID: recordID,
                                          type: type,
                                          version: "",
                                          deleted: false,
                                          compressed: compression != nil)

        ifHaveZone {
            let remoteCompression = compression ?? COMPRESSION_LZFSE

            let recordID = CKRecord.ID(recordName: cloudPath.toRecordID(root: searchPathDirectory),
                        zoneID: CloudKitManager.privateZoneId)

            self.fetchRecord(recordID: recordID,
                             path: cloudPath,
                             searchPathDirectory: searchPathDirectory) { fileSinkiRecords in
                guard let fileSinkiRecord = fileSinkiRecords.first else {
                    onReceive(cloudPath, nil, false)   // no records
                    return
                }

                guard let path = fileSinkiRecord.value(forKey: RecordKey.path.rawValue) as? String else {
                    DebugAssert(false, "CloudKit record \(cloudPath) missing path value")
                    onReceive(cloudPath, nil, false)
                    return
                }

                guard let fileSinkiData: Data = fileSinkiRecord.extractData() else {
                    DebugAssert(false, "CloudKit record \(cloudPath) missing data value")
                                onReceive(cloudPath, nil, false)
                    return
                }

                let isDeleted: Bool = (fileSinkiRecord.value(forKey: RecordKey.deleted.rawValue) as? NSNumber)?.boolValue ?? false

                let recordID: String = fileSinkiRecord.recordID.recordName
                let version: String = fileSinkiRecord.recordChangeTag ?? "Change Tag Missing"
                self.localDB.addLocalKnownFileFor(recordID: recordID,
                                                  type: type,
                                                  version: version,
                                                  deleted: false,
                                                  compressed: compression != nil)

                runAsync {
                    let decompressed = fileSinkiData.decompress(algorithm: remoteCompression) ?? fileSinkiData
                    onReceive(path, decompressed, isDeleted)
                }
            }
        }
    }

    // MARK: Generic Fetching

    typealias FetchAllClosure = ((_ results: [FetchAllResult]) -> ())

    struct FetchAllResult {
        let recordID: String
        let version: String
    }

    func fetchAllRecordsContaining(recordID: String,
                                   onReceive: @escaping FetchAllClosure) {
        ifHaveZone {
            let wildCardMatch = recordID.last == "/"

            let predicate: NSPredicate
            if wildCardMatch {
                let prefixStripped = recordID.recordIDWithFileSinkiPrefixRemoved()
                predicate = NSPredicate(format: "self CONTAINS %@", prefixStripped)
            } else {
                predicate = NSPredicate(format: "\(RecordKey.recordID.rawValue) = %@",
                                        CKRecord.ID(recordName: recordID,
                                                    zoneID: CloudKitManager.privateZoneId))
            }

            self.fetchRecords(predicate: predicate, path: recordID) { fileSinkiRecords in
                var results = [FetchAllResult]()
                for fileSinkiRecord in fileSinkiRecords {
                    guard let version = fileSinkiRecord.recordChangeTag else {
                            continue
                    }
                    if fileSinkiRecord.recordID.recordName.contains(recordID) {
                        results.append(FetchAllResult(recordID: fileSinkiRecord.recordID.recordName,
                                                      version: version))
                    }
                }
                runOnMain {
                    onReceive(results)
                }
            }
        }
    }

    func fetchAllRecordsContaining<T>(recordID: String,
                                      type: T.Type,
                                      onReceive: @escaping FetchAllClosure) where T: FileSyncable {
        ifHaveZone {
            let wildCardMatch = recordID.last == "/"

            let predicate: NSPredicate
            if wildCardMatch {
                let prefixStripped = recordID.recordIDWithFileSinkiPrefixRemoved()
                predicate = NSPredicate(format: "self CONTAINS %@ AND type == %@", prefixStripped,
                                        String(describing: type))
            } else {
                predicate = NSPredicate(format: "\(RecordKey.recordID.rawValue) = %@ AND type == %@",
                                        CKRecord.ID(recordName: recordID,
                                                    zoneID: CloudKitManager.privateZoneId),
                                        String(describing: type))
            }

            self.fetchRecords(predicate: predicate, path: recordID) { fileSinkiRecords in
                var results = [FetchAllResult]()
                for fileSinkiRecord in fileSinkiRecords {
                    guard let version = fileSinkiRecord.recordChangeTag else {
                            continue
                    }
                    if fileSinkiRecord.recordID.recordName.contains(recordID) {
                        results.append(FetchAllResult(recordID: fileSinkiRecord.recordID.recordName,
                                                      version: version))
                    }
                }
                runOnMain {
                    onReceive(results)
                }
            }
        }
    }

    // MARK: - Private fetching and saving

    typealias FetchCompletion = ((_ records: [CKRecord]) -> ())

    private func fetchRecords(predicate: NSPredicate,
                              path: String,
                              fetched: @escaping FetchCompletion) {
        let query = CKQuery(recordType: CloudKitManager.fileSinkiRecordType, predicate: predicate)
        var operation = CKQueryOperation(query: query)
        operation.database = privateDatabase
        operation.zoneID = CloudKitManager.privateZoneId
        operation.configuration.qualityOfService = qualityOfService
        operation.configuration.timeoutIntervalForRequest = 60

        var fileSinkiRecords: [CKRecord] = []

        operation.recordFetchedBlock = { record in
            fileSinkiRecords.append(record)
        }

        operation.queryCompletionBlock = { cursor, error in
            if let cursor = cursor {
                let nextOperation = CKQueryOperation(cursor: cursor)
                nextOperation.zoneID = CloudKitManager.privateZoneId
                nextOperation.recordFetchedBlock = operation.recordFetchedBlock
                nextOperation.queryCompletionBlock = operation.queryCompletionBlock
                nextOperation.resultsLimit = operation.resultsLimit
                operation = nextOperation
                FileSinki.cloudOperationQueue.addOperation(operation)
                return
            }

            if let error = error {
                guard let error = error as? CKError else {
                    self.zoneLoadingLock.lock()
                    DebugLog("Ignoring CloudKit due to unkown error")
                    self.loadingZoneFatalError = true
                    self.zoneLoadingLock.unlock()

                    DebugLog("Couldn't find \(path) in CloudKit \(error)")
                    fetched(fileSinkiRecords)
                    return
                }

                self.zoneLoadingLock.lock()

                let retryTimeout: TimeInterval?

                switch error.code {
                case .notAuthenticated, .internalError,
                        .badContainer, .serviceUnavailable,
                        .missingEntitlement, .permissionFailure,
                        .incompatibleVersion, .constraintViolation,
                        .badDatabase, .quotaExceeded, .managedAccountRestricted,
                        .accountTemporarilyUnavailable:
                    DebugLog("Ignoring CloudKit due to error \(error)")
                    self.loadingZoneFatalError = true   // bail out from cloudkit until next app launch
                    retryTimeout = nil
                    break
                case .requestRateLimited, .zoneBusy:
                    // we'll come back later
                    retryTimeout = error.retryAfterSeconds
                    break
                default:
                    retryTimeout = nil
                    break
                }
                self.zoneLoadingLock.unlock()

                if let retryAfter = retryTimeout {
                    DebugLog("CloudKit rejected with retry timeout: \(retryAfter)")
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + retryAfter,
                                                 execute: { () -> Void in
                                                    self.fetchRecords(predicate: predicate,
                                                                      path: path,
                                                                      fetched: fetched)
                    })
                } else {
                    DebugLog("Couldn't find \(path) in CloudKit \(error)")
                    fetched(fileSinkiRecords)
                }
                return
            } else {
                fetched(fileSinkiRecords)
            }
        }

        FileSinki.cloudOperationQueue.addOperation(operation)
    }

    // MARK: Batched Fetching

    private struct FetchRecordQueueItem {
        let recordID: CKRecord.ID
        let path: String
        let searchPathDirectory: FileManager.SearchPathDirectory
        let fetched: FetchCompletion
    }

    private var fetchRecordQueue = [FetchRecordQueueItem]()

    @objc private func runFetchRecordQueue() {
        guard !fetchingRecordBatch else {
            return
        }
        let maxRecordsPerBatch: Int = 99

        var batch = [FetchRecordQueueItem]()

        var recordsRemaining = maxRecordsPerBatch
        while !fetchRecordQueue.isEmpty && recordsRemaining > 0 {
            batch.append(fetchRecordQueue.removeFirst())
            recordsRemaining -= 1
        }

        debouncedRecordFetch()

        fetchRecordBatch(batch)
    }

    private func debouncedRecordFetch() {
        runOnMain {
            if !self.fetchRecordQueue.isEmpty {
                let dedupeTime: TimeInterval = 0.2
                NSObject.cancelPreviousPerformRequests(withTarget: self)

                self.perform(#selector(self.runFetchRecordQueue),
                             with: nil,
                             afterDelay: dedupeTime)
            }
        }
    }

    private var fetchingRecordBatch: Bool = false

    private func fetchRecordBatch(_ batch: [FetchRecordQueueItem]) {
        guard batch.count > 0 else { return }

        fetchingRecordBatch = true

        let operation = CKFetchRecordsOperation(recordIDs: batch.map { $0.recordID })

        operation.database = privateDatabase
        operation.configuration.qualityOfService = qualityOfService
        operation.configuration.timeoutIntervalForRequest = 60

        operation.fetchRecordsCompletionBlock = { records, error in
            self.fetchingRecordBatch = false

            if let error = error {
                guard let error = error as? CKError else {
                    self.zoneLoadingLock.lock()
                    DebugLog("Ignoring CloudKit due to unkown error")
                    self.loadingZoneFatalError = true
                    self.zoneLoadingLock.unlock()

                    for item in batch {
                        if let record = records?[item.recordID] {
                            item.fetched([record])
                        } else {
                            item.fetched([])
                        }
                    }
                    return
                }

                self.zoneLoadingLock.lock()

                let retryTimeout: TimeInterval?

                switch error.code {
                case .notAuthenticated, .internalError,
                        .badContainer, .serviceUnavailable,
                        .missingEntitlement, .permissionFailure,
                        .incompatibleVersion, .constraintViolation,
                        .badDatabase, .quotaExceeded, .managedAccountRestricted,
                        .accountTemporarilyUnavailable:
                    DebugLog("Ignoring CloudKit due to error \(error)")
                    self.loadingZoneFatalError = true   // bail out from cloudkit until next app launch
                    retryTimeout = nil
                    break
                case .requestRateLimited, .zoneBusy:
                    // we'll come back later
                    retryTimeout = error.retryAfterSeconds
                    break
                default:
                    retryTimeout = nil
                    break
                }
                self.zoneLoadingLock.unlock()

                if let retryAfter = retryTimeout {
                    DebugLog("CloudKit rejected with retry timeout: \(retryAfter)")
                       DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + retryAfter,
                                                     execute: { () -> Void in
                                                        self.fetchRecordBatch(batch)
                       })
                } else {
                    for item in batch {
                        if let record = records?[item.recordID] {
                            item.fetched([record])
                        } else {
                            item.fetched([])
                        }
                    }
                }
                return
            } else {
                // success
                for item in batch {
                    if let record = records?[item.recordID] {
                        item.fetched([record])
                    } else {
                        DebugLog("Couldn't find \(item.path) in CloudKit")
                        item.fetched([])
                    }
                }
            }
            self.debouncedRecordFetch()
        }

        FileSinki.cloudOperationQueue.addOperation(operation)
    }

    private func fetchRecord(recordID: CKRecord.ID,
                             path: String,
                             searchPathDirectory: FileManager.SearchPathDirectory,
                             fetched: @escaping FetchCompletion) {
        runOnMain {
            let queueItem = FetchRecordQueueItem(recordID: recordID,
                                                 path: path,
                                                 searchPathDirectory: searchPathDirectory,
                                                 fetched: fetched)
            self.fetchRecordQueue.append(queueItem)

            self.debouncedRecordFetch()
        }
    }

    // MARK: Saving and Deleting

    private func saveOrDeleteRecord<T>(recordID: String,
                                       cloudPath: String,
                                       searchPathDirectory: FileManager.SearchPathDirectory,
                                       originalItem: T,
                                       data: Data,
                                       delete: Bool,
                                       compression: compression_algorithm?,
                                       finalVersion: ((_ item: T) -> ())?) where T: FileSyncable {
        let remoteCompression = compression ?? COMPRESSION_LZFSE

        var dataToWrite: Data

        if remoteCompression == compression {
            dataToWrite = data
        } else {
            dataToWrite = originalItem.compress(with: remoteCompression) ?? data
        }

        let typeString = String(describing: type(of: originalItem))

        fetchRecord(recordID: CKRecord.ID(recordName: cloudPath.toRecordID(root: searchPathDirectory),
                                          zoneID: CloudKitManager.privateZoneId),
                    path: cloudPath,
                    searchPathDirectory: searchPathDirectory) { fileSinkiRecords in
            let sendRecordToCloud = { record in
                self.saveRecord(record,
                                cloudPath: cloudPath,
                                originalItem: originalItem,
                                tmpFileToDelete: nil,
                                compression: compression,
                                retry: { [weak self] in
                    self?.saveOrDeleteRecord(recordID: recordID,
                                             cloudPath: cloudPath,
                                             searchPathDirectory: searchPathDirectory,
                                             originalItem: originalItem,
                                             data: dataToWrite,
                                             delete: delete,
                                             compression: compression,
                                             finalVersion: finalVersion)
                })
            }


            if let existingRecord = fileSinkiRecords.first {
                if delete {
                    // skip any merging or overwite checks
                    let alreadyDeleted: Bool = (existingRecord.value(forKey: RecordKey.deleted.rawValue) as? NSNumber)?.boolValue ?? false
                    if alreadyDeleted {
                        DebugLog("iCloud version of \(cloudPath) was already deleted")
                        return
                    }
                    existingRecord.setData(cloudPath: cloudPath, data: dataToWrite, deleted: delete, type: typeString)
                    sendRecordToCloud(existingRecord)
                    return
                } else if let existingCloudData = existingRecord.extractData(),
                    let existingDecoded = T.decodeFrom(data: existingCloudData, compression: remoteCompression) {

                    runAsync {
                        existingDecoded.mergeAsync(with: originalItem) { merged in
                            if let merged = merged {
                                runOnMain {
                                    guard merged != existingDecoded else {
                                        DebugLog("iCloud version of \(cloudPath) was the same, not overwriting")
                                        self.localDB.addLocalKnownFileFor(recordID: recordID,
                                                                          type: T.self,
                                                                          version: existingRecord.recordChangeTag ?? "",
                                                                          deleted: false,
                                                                          compressed: compression != nil)
                                        return  // icloud version is same after merge, don't overwrite
                                    }
                                    DebugLog("Merging \(cloudPath) with iCloud version")

                                    runAsync {
                                        // need to reserialize and compress
                                        if let compressedData = merged.saveLocalTo(fileURL: cloudPath.localURLFromCloudPath(for: searchPathDirectory),
                                                                                   compression: compression) {
                                            if remoteCompression == compression {
                                                dataToWrite = compressedData
                                            } else if let remoteCompressed = merged.compress(with: remoteCompression) {
                                                dataToWrite = remoteCompressed
                                            }
                                            runOnMain {
                                                existingRecord.setData(cloudPath: cloudPath, data: dataToWrite, deleted: delete, type: typeString)
                                                sendRecordToCloud(existingRecord)
                                                finalVersion?(merged)
                                            }
                                        } else {
                                            DebugAssert(false, "Failed to save merged file \(cloudPath) to local")
                                        }
                                    }
                                }
                            } else {
                                // fall back to overwrite check
                                runOnMain {
                                    originalItem.shouldOverwriteAsync(other: existingDecoded) { winner in
                                        if winner == existingDecoded {
                                            DebugLog("iCloud version of \(cloudPath) was better or same, not overwriting")
                                            if originalItem != existingDecoded {
                                                finalVersion?(existingDecoded)
                                            }

                                            self.localDB.addLocalKnownFileFor(recordID: recordID,
                                                                              type: T.self,
                                                                              version: existingRecord.recordChangeTag ?? "",
                                                                              deleted: false,
                                                                              compressed: compression != nil)
                                        } else {
                                            existingRecord.setData(cloudPath: cloudPath, data: dataToWrite, deleted: delete, type: typeString)
                                            sendRecordToCloud(existingRecord)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                return
            }

            // new record
            let record = CKRecord(recordType: CloudKitManager.fileSinkiRecordType,
                                  recordID: CKRecord.ID(recordName: cloudPath.toRecordID(root: searchPathDirectory),
                                                        zoneID: CloudKitManager.privateZoneId))
            record.setData(cloudPath: cloudPath, data: data, deleted: delete, type: typeString)
            sendRecordToCloud(record)
        }

    }

    private var retrySaveQueue = [String: [(() -> ())]]()

    private var inflightSave = [String: Bool]()

    private let inflightSaveLock = NSLock()

    private func saveRecord<T>(_ record: CKRecord,
                               cloudPath: String,
                               originalItem: T,
                               tmpFileToDelete: URL?,
                               compression: compression_algorithm?,
                               retry: @escaping (() -> ())) where T: FileSyncable {
        inflightSaveLock.lock()
        guard inflightSave[cloudPath] != true else {
            DebugLog("Slowing \(cloudPath) record save requests")

            if var existing = retrySaveQueue[cloudPath] {
                existing.append(retry)
                retrySaveQueue[cloudPath] = existing
            } else {
                retrySaveQueue[cloudPath] = [retry]
            }
            inflightSaveLock.unlock()
            return
        }

        inflightSave[cloudPath] = true
        inflightSaveLock.unlock()

        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.database = privateDatabase
        operation.configuration.qualityOfService = qualityOfService
        operation.configuration.timeoutIntervalForRequest = 60
        operation.isAtomic = false

        operation.perRecordCompletionBlock = { [weak self] ckRecord, error in
            guard let self = self else { return }


            if let error = error {
                guard let error = error as? CKError else {
                    self.zoneLoadingLock.lock()
                    DebugLog("Ignoring CloudKit due to unkown error")
                    self.loadingZoneFatalError = true
                    self.zoneLoadingLock.unlock()
                    return
                }

                self.zoneLoadingLock.lock()

                let retryTimeout: TimeInterval?

                switch error.code {
                case .serverRecordChanged:
                    // record has changed since we fetched, need to try again.
                    self.zoneLoadingLock.unlock()

                    DebugLog("\(cloudPath) server record has changed since fetch. Trying again.")
                    DispatchQueue.main.async {
                        self.inflightSaveLock.lock()
                        self.inflightSave[cloudPath] = false
                        self.inflightSaveLock.unlock()

                        retry()
                    }
                    return
                case .limitExceeded:
                    DebugLog("File for \(cloudPath) was too big for CloudKit, saving data as an Asset")
                    self.zoneLoadingLock.unlock()
                    record.moveDataToAsset { tmpFileToDelete in
                        self.inflightSaveLock.lock()
                        self.inflightSave[cloudPath] = false
                        self.inflightSaveLock.unlock()

                        self.saveRecord(record,
                                        cloudPath: cloudPath,
                                        originalItem: originalItem,
                                        tmpFileToDelete: tmpFileToDelete,
                                        compression: compression,
                                        retry: retry)
                    }
                    return
                case .notAuthenticated, .internalError,
                        .badContainer, .serviceUnavailable,
                        .missingEntitlement, .permissionFailure,
                        .incompatibleVersion, .constraintViolation,
                        .badDatabase, .quotaExceeded, .managedAccountRestricted,
                        .accountTemporarilyUnavailable:
                    DebugLog("Ignoring CloudKit due to error \(error)")
                    self.loadingZoneFatalError = true   // bail out from cloudkit until next app launch
                    retryTimeout = nil
                    break
                case .requestRateLimited, .zoneBusy:
                    // we'll come back later
                    retryTimeout = error.retryAfterSeconds
                    break
                default:
                    retryTimeout = nil
                    break
                }
                self.zoneLoadingLock.unlock()

                if let retryAfter = retryTimeout {
                    DebugLog("CloudKit rejected with retry timeout: \(retryAfter)")
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + retryAfter,
                                                  execute: { () -> Void in

                        self.inflightSaveLock.lock()
                        self.inflightSave[cloudPath] = false
                        self.inflightSaveLock.unlock()

                        self.saveRecord(record,
                                        cloudPath: cloudPath,
                                        originalItem: originalItem,
                                        tmpFileToDelete: tmpFileToDelete,
                                        compression: compression,
                                        retry: retry)
                     })
                    return
                } else {
                    DebugLog("Failed to save \(cloudPath) record to CloudKit \(error)")
                }
                return
            } else {
                // success
                if let tmpFileToDelete = tmpFileToDelete {
                    try? FileManager.default.removeItem(at: tmpFileToDelete)
                }
                DebugLog("Saved \(cloudPath) record to CloudKit")

                let recordID: String = ckRecord.recordID.recordName
                let version: String = ckRecord.recordChangeTag ?? "Change Tag Missing"

                self.localDB.addLocalKnownFileFor(recordID: recordID,
                                                  type: T.self,
                                                  version: version,
                                                  deleted: false,
                                                  compressed: compression != nil)

                self.inflightSaveLock.lock()
                self.inflightSave[cloudPath] = false
                self.inflightSaveLock.unlock()

                DispatchQueue.main.async {

                    self.inflightSaveLock.lock()
                    if var retryQueue = self.retrySaveQueue[cloudPath],
                       !retryQueue.isEmpty,
                        self.inflightSave[cloudPath] != true {
                        DebugLog("Doing deferred \(cloudPath) record save to CloudKit")

                        let retry = retryQueue.removeFirst()
                        self.retrySaveQueue[cloudPath] = retryQueue

                        self.inflightSaveLock.unlock()
                        retry()
                    } else {
                        self.inflightSaveLock.unlock()
                    }
                }
            }
        }

        FileSinki.cloudOperationQueue.addOperation(operation)
    }

    // MARK: - Notification Subscription

    func addNotificationSubscription(recordID: String) {
        ifHaveZone {
            let wildCardMatch = recordID.last == "/"

            let predicate: NSPredicate
            if wildCardMatch {
                let prefixStripped = recordID.recordIDWithFileSinkiPrefixRemoved()
                predicate = NSPredicate(format: "self CONTAINS %@", prefixStripped)
            } else {
                predicate = NSPredicate(format: "\(RecordKey.recordID.rawValue) = %@",
                                        CKRecord.ID(recordName: recordID,
                                                    zoneID: CloudKitManager.privateZoneId))
            }

            let subscription = CKQuerySubscription(recordType: CloudKitManager.fileSinkiRecordType,
                                                   predicate: predicate,
                                                   subscriptionID: CKSubscription.ID("Remote Changes"),
                                                   options: [.firesOnRecordCreation,
                                                             .firesOnRecordUpdate,
                                                             .firesOnRecordDeletion])

            let notificationInfo = CKSubscription.NotificationInfo()
            notificationInfo.__desiredKeys = [CloudKitManager.RecordKey.path.rawValue]
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo

            let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription],
                                                           subscriptionIDsToDelete: nil)
            operation.database = self.privateDatabase
            operation.configuration.qualityOfService = self.qualityOfService
            operation.configuration.timeoutIntervalForRequest = 60

            operation.modifySubscriptionsCompletionBlock = { (modifiedSubscriptions: [CKSubscription]?, deletedSubscriptionIDs: [String]?, saveError: Error?) -> Void in
                if let error = saveError {
                    if (error as NSError).code != CKError.Code.partialFailure.rawValue {
                        DebugLog("Failed to save CloudKit notification subscription for \(recordID), error: \(error)")
                    }
                }
                DebugLog("Subscribed for notification changes to \(recordID)")
            }
            FileSinki.cloudOperationQueue.addOperation(operation)
        }
    }

    // MARK: - Zone Creation

    private var haveZone: Bool = false

    private var loadingZone: Bool = false

    private var loadingZoneFatalError: Bool = false

    private var onZoneLoaded = [() -> ()]()

    private let zoneLoadingLock = NSLock()

    func ifHaveZone(_ doWork: @escaping () -> ()) {
        zoneLoadingLock.lock()
        if loadingZoneFatalError {
            zoneLoadingLock.unlock()
            return
        }
        if haveZone {
            zoneLoadingLock.unlock()
            doWork()
            return
        }
        if onZoneLoaded.count < 1000 {  // a sensible yet high limit
            onZoneLoaded.append(doWork)
        }
        let currentlyLoading = loadingZone
        zoneLoadingLock.unlock()
        if !currentlyLoading {
            createFileSinkiZone()
        }
    }

    private func createFileSinkiZone() {
        zoneLoadingLock.lock()
        guard !loadingZone, !haveZone, !loadingZoneFatalError else {
            zoneLoadingLock.unlock()
            return
        }

        loadingZone = true

        zoneLoadingLock.unlock()

        let zone = CKRecordZone(zoneID: CloudKitManager.privateZoneId)
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        operation.database = privateDatabase
        operation.configuration.qualityOfService = qualityOfService

        operation.modifyRecordZonesCompletionBlock = { savedZones, deletedZoneIds, error in
            if let error = error {
                guard let error = error as? CKError else {
                    self.zoneLoadingLock.lock()
                    self.haveZone = false
                    self.loadingZone = false
                    DebugLog("Ignoring CloudKit due to unkown error")
                    self.loadingZoneFatalError = true
                    self.zoneLoadingLock.unlock()
                    return
                }

                self.zoneLoadingLock.lock()

                switch error.code {
                case .notAuthenticated, .internalError, .partialFailure,
                        .badContainer, .serviceUnavailable,
                        .missingEntitlement, .permissionFailure,
                        .incompatibleVersion, .constraintViolation,
                        .badDatabase, .quotaExceeded, .managedAccountRestricted,
                        .accountTemporarilyUnavailable:
                    DebugLog("Ignoring CloudKit due to error \(error)")
                    self.loadingZoneFatalError = true
                    self.onZoneLoaded.removeAll()
                    break
                case .requestRateLimited, .zoneBusy:
                    // we'll come back later
                    break
                default:
                    break
                }
                self.haveZone = false
                self.loadingZone = false

                self.zoneLoadingLock.unlock()
                return
            }

            runOnMain {
                DebugLog("CloudKit Zone ready")

                self.zoneLoadingLock.lock()
                let copy = self.onZoneLoaded
                self.onZoneLoaded.removeAll()
                self.haveZone = true
                self.loadingZone = false
                self.zoneLoadingLock.unlock()

                for completion in copy {
                    completion()
                }
            }
        }
        FileSinki.cloudOperationQueue.addOperation(operation)
    }

}

// MARK: - CKRecord Helpers

fileprivate extension CKRecord {

    func setData(cloudPath: String, data: Data, deleted: Bool, type: String) {
        setValue(cloudPath, forKey: CloudKitManager.RecordKey.path.rawValue)
        setValue(data, forKey: CloudKitManager.RecordKey.data.rawValue)
        setValue(nil, forKey: CloudKitManager.RecordKey.asset.rawValue)
        setValue(NSNumber(value: deleted), forKey: CloudKitManager.RecordKey.deleted.rawValue)
        setValue(type, forKey: CloudKitManager.RecordKey.type.rawValue)
    }

    func moveDataToAsset(_ then: @escaping (_ tmpFileToDelete: URL) -> ()) {
        guard let data = self.value(forKey: CloudKitManager.RecordKey.data.rawValue) as? Data else {
            DebugAssert(false, "Expected a data object in \(self) to convert to an asset")
            return
        }
        let tmpFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        runAsync {
            do {
                try data.write(to: tmpFile, options: .atomic)
            } catch {
                DebugAssert(false, "Could not write asset to tmp file \(tmpFile)")
                return
            }
            let asset = CKAsset(fileURL: tmpFile)
            runOnMain {
                self.setValue(asset, forKey: CloudKitManager.RecordKey.asset.rawValue)
                self.setValue(nil, forKey: CloudKitManager.RecordKey.data.rawValue)
                then(tmpFile)
            }
        }
    }

    func extractData() -> Data? {
        if let data = self.value(forKey: CloudKitManager.RecordKey.data.rawValue) as? Data {
            return data
        } else if let asset = self.value(forKey: CloudKitManager.RecordKey.asset.rawValue) as? CKAsset,
            let assetFileURL = asset.fileURL,
            let data = try? Data(contentsOf: assetFileURL) {
            return data
        } else {
            DebugAssert(false, "CloudKit record \(self) missing data value")
            return nil
        }
    }
}
