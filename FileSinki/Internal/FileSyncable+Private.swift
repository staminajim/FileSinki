//
//  Mergable+Internal.swift
//  LocoLooper
//
//  Created by James Van-As on 4/05/20.
//  Copyright © 2020 Fat Eel Studios. All rights reserved.
//

import Foundation
import Compression

// MARK: - Default Implementations

extension FileSyncable {

    // default implementation just uses the non interactive version
    func interactiveShouldOverwrite(other: Self, keep: @escaping ShouldOverwriteClosure) {
        if other.shouldOverwrite(other: self) {
            keep(other)
        } else {
            keep(self)
        }
    }

    // default implementation does nothing, and so falls back to no merging using Comparable.
    func merge(with other: Self) -> Self? {
        return nil
    }

    // default implementation just uses the non interactive version
    func interactiveMerge(with other: Self, merged: @escaping MergedClosure) {
        merged(self.merge(with: other))
    }

    // default implementation allows local deletion from the cloud
    static func shouldDelete(local: Self, remoteDeleted: Self) -> Bool {
        return true
    }

    // default implementation just uses the non interactive version
    static func interactiveShouldDelete(local: Self, remoteDeleted: Self, delete: @escaping ShouldDeleteClosure) {
        delete(shouldDelete(local: local, remoteDeleted: remoteDeleted))
    }

}

extension FileSyncable where Self: Comparable {

    // default implementation does nothing, and so falls back to no merging using Comparable.
    func shouldOverwrite(other: Self) -> Bool {
        return self > other
    }

}

extension FileMergable where Self: FileSyncable {

    // default implementation returns false as we want to perform a merge
    func shouldOverwrite(other: Self) -> Bool {
        return false
    }

}

// MARK: iCloud Compatible Saving and loading

internal extension FileSyncable {

    /**
    Saves the Encodable item locally for a given local file URL, and optionally also saves to the Cloud

    - Parameter fileURL: Local file url to save to
    - Parameter saveToCloud: If true, also saves the file to the cloud.
    - Parameter compression: Which compression algorithm to use, if any. Defaults to zlib.
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */
    @discardableResult func saveTo(fileURL: URL,
                                   searchPathDirectory: FileManager.SearchPathDirectory,
                                   saveToCloud: Bool,
                                   compression: compression_algorithm?,
                                   finalVersion: @escaping (_ item: Self) -> ()) -> Data? {
        let saveData = saveLocalTo(fileURL: fileURL, compression: compression)

        if saveToCloud, let payloadData = saveData {
            saveDataToCloud(fileURL: fileURL,
                            searchPathDirectory: searchPathDirectory,
                            compression: compression,
                            payloadData: payloadData,
                            finalVersion: finalVersion)
        }

        return saveData
    }

    /**
    Loads the Encodable item locally for a given local file URL, and optionally also loads from the Cloud.

    - Parameter fileURL: Local file url to load from
    - Parameter loadFromCloud: If true, also loads the file from the cloud asyncronously.
    - Parameter compression: Which compression algorithm to use, if any. Defaults to zlib.
    - Parameter loaded: The Decoded item. nil if no item has been successfully decoded.

     Note: The loaded completion can be called multple times as data loads in from disk or the cloud,
     with the most up to date copy of the Decodable being returned last.
    */
    static func loadFrom(fileURL: URL,
                         searchPathDirectory: FileManager.SearchPathDirectory,
                         loadFromCloud: Bool,
                         compression: compression_algorithm? = COMPRESSION_LZFSE,
                         binaryMerge: BinaryFileMergeClosure?,
                         loaded: @escaping (_ item: Self?, _ wasRemote: Bool) -> ()) {

        let local = self.decodeFromLocal(fileURL: fileURL,
                                         compression: compression,
                                         binaryMerge: binaryMerge)

        runOnMain {
            loaded(local.decoded, false)

            if loadFromCloud {
                FileSinki.cloudKitManager.loadDataFromCloud(fileURL: fileURL,
                                                            type: self,
                                                            searchPathDirectory: searchPathDirectory,
                                                            compression: compression) { (dataPath, decompressedData, remoteIsDeleted) in
                    // we'll come in here on a non main thread
                    guard let decompressedCloudData = decompressedData else {
                        // save our local copy to icloud also, there's no cloudkit copy.
                        // It'll be rejected later on if we've saved in the meantime and it's not as good as the cloud copy
                        if let localDecoded = local.decoded, let localPayloadData = local.payloadData {
                            runOnMain {
                                DebugLog("Adding file to CloudKit \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path)")

                                localDecoded.saveDataToCloud(fileURL: fileURL,
                                                             searchPathDirectory: searchPathDirectory,
                                                             compression: compression,
                                                             payloadData: localPayloadData,
                                                             finalVersion: { loaded($0, true) })
                            }
                        }
                        return
                    }

                    guard let iCloudDecoded = try? JSONDecoder().decode(Self.self,
                                                                        from: decompressedCloudData) else { return }

                    if let localDecoded = local.decoded {
                        if remoteIsDeleted {
                            runOnMain {
                                Self.interactiveShouldDelete(local: localDecoded, remoteDeleted: iCloudDecoded) { shouldDelete in
                                    if shouldDelete {
                                        // we need to remove our local copy
                                        runOnMain {
                                            DebugLog("CloudKit copy of \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path) was deleted. Deleting local copy.")
                                            localDecoded.deleteLocal(fileURL: fileURL, compression: compression)
                                            loaded(nil, true)
                                        }
                                    } else {
                                        // we need to update the cloud version to be undeleted
                                        if let localPayloadData = local.payloadData {
                                            runOnMain {
                                               DebugLog("CloudKit copy of \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path) was deleted. Undeleting.")
                                                localDecoded.saveDataToCloud(fileURL: fileURL,
                                                                             searchPathDirectory: searchPathDirectory,
                                                                             compression: compression,
                                                                             payloadData: localPayloadData,
                                                                             finalVersion: { loaded($0, true) })
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            runOnMain {
                                iCloudDecoded.interactiveMerge(with: localDecoded) { merged in
                                    runOnMain {
                                        if let merged = merged {
                                            guard merged != localDecoded else {
                                                return  // we haven't changed, no need to do anything
                                            }
                                            runAsync {
                                                if let compressedMerged = merged.saveLocalTo(fileURL: fileURL,
                                                                                             compression: compression) {
                                                    // Merged copy is different to cloud / local. save to disk and upload to cloud
                                                    runOnMain {
                                                        DebugLog("Merged \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path) with CloudKit")
                                                        merged.saveDataToCloud(fileURL: fileURL,
                                                                               searchPathDirectory: searchPathDirectory,
                                                                               compression: compression,
                                                                               payloadData: compressedMerged,
                                                                               finalVersion: { loaded($0, true) })
                                                    }
                                                }

                                                runOnMain {
                                                    DebugLog("Merged \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path) with CloudKit copy")
                                                    loaded(merged, true)
                                                }
                                            }
                                        } else if iCloudDecoded != localDecoded {
                                            // fall back to overwrite checks
                                            iCloudDecoded.interactiveShouldOverwrite(other: localDecoded) { winner in
                                                runOnMain {
                                                    if winner == iCloudDecoded {
                                                        // icloud copy is deemed better than local. save to disk and update
                                                        runAsync {
                                                            iCloudDecoded.write(uncompressedData: decompressedCloudData,
                                                                               toFileURL: fileURL,
                                                                               compression: compression)

                                                            runOnMain {
                                                                DebugLog("Received better version of \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path) from CloudKit")
                                                                loaded(iCloudDecoded, true)
                                                            }
                                                        }
                                                    } else {
                                                        // local version is better than the cloud, push our version up
                                                        if let localPayloadData = local.payloadData {
                                                            runOnMain {
                                                                DebugLog("Local version of \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path) was better than CloudKit. Uploading.")
                                                               localDecoded.saveDataToCloud(fileURL: fileURL,
                                                                                            searchPathDirectory: searchPathDirectory,
                                                                                            compression: compression,
                                                                                            payloadData: localPayloadData,                                                                                            
                                                                                            finalVersion: { loaded($0, true) })
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else if !remoteIsDeleted {
                        // no local copy, use the icloud one, and save to disk
                        iCloudDecoded.write(uncompressedData: decompressedCloudData,
                                            toFileURL: fileURL,
                                            compression: compression)
                        runOnMain {
                            DebugLog("Received \(fileURL.cloudPath(for: searchPathDirectory) ?? fileURL.path) from CloudKit")
                            loaded(iCloudDecoded, true)
                        }
                    }
                }

            }
        }

    }

    /**
    Saves the Encodable item locally for a given local file URL, and optionally also saves to the Cloud

    - Parameter fileURL: Local file url to save to
    - Parameter saveToCloud: If true, also saves the file to the cloud.
    - Parameter compression: Which compression algorithm to use, if any. Defaults to zlib.
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */
    func delete(fileURL: URL,
                searchPathDirectory: FileManager.SearchPathDirectory,
                saveToCloud: Bool,
                compression: compression_algorithm? = COMPRESSION_LZFSE) {
        deleteLocal(fileURL: fileURL, compression: compression)

        if saveToCloud {
            deleteDataInCloud(fileURL: fileURL, searchPathDirectory: searchPathDirectory, compression: compression)
        }
    }

}


// MARK: - Cloud Saving

internal extension FileSyncable {

    func saveDataToCloud(fileURL: URL,
                         searchPathDirectory: FileManager.SearchPathDirectory,
                         compression: compression_algorithm?,
                         finalVersion: @escaping (_ item: Self) -> ()) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let jsonData = try? encoder.encode(self) else {
            DebugAssert(false, "Failed to encode save state json \(String(describing: self))")
            return
        }
        if let compression = compression,
            let zipData = jsonData.compress(algorithm: compression) {
            FileSinki.cloudKitManager.saveDataToCloud(fileURL: fileURL,
                                                      searchPathDirectory: searchPathDirectory,
                                                      originalItem: self,
                                                      data: zipData,
                                                      compression: compression,
                                                      finalVersion: finalVersion)
        } else {
            FileSinki.cloudKitManager.saveDataToCloud(fileURL: fileURL,
                                                      searchPathDirectory: searchPathDirectory,
                                                      originalItem: self,
                                                      data: jsonData,
                                                      compression: compression,
                                                      finalVersion: finalVersion)
        }
    }

    func saveDataToCloud(fileURL: URL,
                         searchPathDirectory: FileManager.SearchPathDirectory,
                         compression: compression_algorithm?,
                         payloadData: Data,
                         finalVersion: @escaping (_ item: Self) -> ()) {
        FileSinki.cloudKitManager.saveDataToCloud(fileURL: fileURL,
                                                  searchPathDirectory: searchPathDirectory,
                                                  originalItem: self,
                                                  data: payloadData,
                                                  compression: compression,
                                                  finalVersion: finalVersion)
    }

    func deleteDataInCloud(fileURL: URL,
                           searchPathDirectory: FileManager.SearchPathDirectory,
                           compression: compression_algorithm?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let jsonData = try? encoder.encode(self) else {
            DebugAssert(false, "Failed to encode save state json \(String(describing: self))")
            return
        }
        if let compression = compression,
            let zipData = jsonData.compress(algorithm: compression) {
            FileSinki.cloudKitManager.deleteDataInCloud(fileURL: fileURL,
                                                        searchPathDirectory: searchPathDirectory,
                                                        originalItem: self,
                                                        data: zipData,
                                                        compression: compression)
        } else {
            FileSinki.cloudKitManager.deleteDataInCloud(fileURL: fileURL,
                                                        searchPathDirectory: searchPathDirectory,
                                                        originalItem: self,
                                                        data: jsonData,
                                                        compression: compression)
        }

    }

    func deleteLocal(fileURL: URL,
                     compression: compression_algorithm?) {
        do {
            try FileManager.default.removeItem(at: fileURL.withCompressionSuffix(compression))
        } catch {
            DebugLog("Failed to delete file at \(fileURL)")
        }
    }

}
