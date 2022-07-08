//
//  LocalDatabase.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 6/05/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation
import Compression

internal struct FileSinkiRecord: Codable, Equatable {
    let recordID: String
    let version: String
    let pendingSave: Bool
    let deleted: Bool
    let type: String
    let compressed: Bool

    init<T>(recordID: String,
            type: T.Type,
            version: String,
            pendingSave: Bool,
            deleted: Bool,
            compressed: Bool) where T: FileSyncable {
        self.recordID = recordID
        self.version = version
        self.pendingSave = pendingSave
        self.deleted = deleted
        self.type = String(describing: type)
        self.compressed = compressed
    }
}

internal final class LocalDatabase: NSObject {

    private let compression = COMPRESSION_LZFSE

    override init() {
        knownLocalFiles = [String: FileSinkiRecord].loadFromLocal(fileURL: LocalDatabase.knownLocalFilesURL,
                                                                  compression: compression) ?? [String: FileSinkiRecord]()
        super.init()
    }

    // MARK: - Type Map

    private var typeMap = [String: Any.Type]()

    func registerKnownType<T: FileSyncable>(_ type: T.Type) {
        let newRecord = String(describing: type)
        guard self.typeMap[newRecord] == nil else {
            return
        }
        self.typeMap[newRecord] = type
        processPendingSaveAndFetchList(type: type)

        FileSinki.reachability.addPermanentRetryOperation( {
            self.processPendingSaveAndFetchList(type: type)            
        })
    }

    // MARK: - Pending Saves

    func addPendingSaveRecordFor<T>(recordID: String,
                                    type: T.Type,
                                    compressed: Bool) where T: FileSyncable {
        runOnMain {
            self.registerKnownType(type)

            let newRecord = FileSinkiRecord(recordID: recordID,
                                            type: type,
                                            version: "",
                                            pendingSave: true,
                                            deleted: false,
                                            compressed: compressed)
            guard self.knownLocalFiles[recordID] != newRecord else {
                return
            }
            self.knownLocalFiles[recordID] = newRecord

            let dedupeTime: TimeInterval = 1
            NSObject.cancelPreviousPerformRequests(withTarget: self)

            self.perform(#selector(self.saveLocalKnownFiles),
                         with: nil,
                         afterDelay: dedupeTime)
        }
    }

    // MARK: - Any Known Local FileSinki Files

    private var knownLocalFiles: [String: FileSinkiRecord]

    private static var knownLocalFilesURL: URL {
        return FileSinki.defaultRootFolder.appendingPathComponent("FileSinki/known", isDirectory: false)
    }

    func addLocalKnownFileFor<T>(recordID: String,
                                 type: T.Type,
                                 version: String,
                                 deleted: Bool,
                                 compressed: Bool) where T: FileSyncable {
        runOnMain {
            self.registerKnownType(type)

            let newRecord = FileSinkiRecord(recordID: recordID,
                                            type: type,
                                            version: version,
                                            pendingSave: false,
                                            deleted: deleted,
                                            compressed: compressed)
            guard self.knownLocalFiles[recordID] != newRecord else {
                return
            }
            self.knownLocalFiles[recordID] = newRecord

            let dedupeTime: TimeInterval = 1
            NSObject.cancelPreviousPerformRequests(withTarget: self)

            self.perform(#selector(self.saveLocalKnownFiles),
                         with: nil,
                         afterDelay: dedupeTime)
        }
    }

    func removeLocalKnownFileFor(recordID: String) {
        runOnMain {
            guard let _ = self.knownLocalFiles.removeValue(forKey: recordID) else {
                return
            }
            let dedupeTime: TimeInterval = 1
            NSObject.cancelPreviousPerformRequests(withTarget: self)

            self.perform(#selector(self.saveLocalKnownFiles),
                         with: nil,
                         afterDelay: dedupeTime)
        }
    }

    func knownFilesMatching(recordID: String) -> [FileSinkiRecord] {
        let wildCardMatch = recordID.last == "/"

        var matching = [FileSinkiRecord]()
        for (key, record) in knownLocalFiles {
            if wildCardMatch {
                if key.contains(recordID) {
                    matching.append(record)
                }
            } else {
                if key == recordID {
                    matching.append(record)
                }
            }
        }
        return matching
    }

    // MARK: - Saving

    @objc private func saveLocalKnownFiles() {
        let copy = self.knownLocalFiles
        runAsync {
            copy.saveLocalTo(fileURL: LocalDatabase.knownLocalFilesURL, compression: self.compression)
        }
    }

    // MARK: - Automatic fetching and refetching of things

    private func processPendingSaveAndFetchList<T: FileSyncable>(type: T.Type) {
        let typeString = String(describing: type)

        var pendingRecords = [FileSinkiRecord]()
        var pendingFetchRecords = [FileSinkiRecord]()

        for (_, record) in self.knownLocalFiles {
            guard typeString == record.type,
                type != BinaryFileSyncable.self else {   // binary files require an interactive merge closure
                continue
            }
            if record.pendingSave {
                pendingRecords.append(record)
            } else if record.version == "" {
                pendingFetchRecords.append(record)
            }
        }

        for pending in pendingRecords {
            // trigger a local load which will also attempt to save again
            guard let url = pending.recordID.recordIDToLocalURL() else {
                continue
            }
            DebugLog("Doing delayed save for \(pending.recordID)")
            if pending.compressed {
                FileSinki.loadCompressed(type, fromPath: url.path) { _,_  in }
            } else {
                FileSinki.load(type, fromPath: url.path) { _,_  in }
            }
        }

        for fetch in pendingFetchRecords {
            // trigger a local load which will also attempt to save again
            guard let url = fetch.recordID.recordIDToLocalURL() else {
                continue
            }
            DebugLog("Doing delayed load for \(fetch.recordID)")
            if fetch.compressed {
                FileSinki.loadCompressed(type, fromPath: url.path) { _,_  in }
            } else {
                FileSinki.load(type, fromPath: url.path) { _,_  in }
            }
        }
    }

}

