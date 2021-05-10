//
//  BinaryFileSyncable.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 4/05/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation
import Compression

internal struct BinaryFileSyncable: FileSyncable, FileMergable {

    let modifiedDate: Date

    let binaryData: Data

    var mergeAsyncClosure: BinaryFileMergeClosure?

    enum CodingKeys: String, CodingKey {
        case modifiedDate
        case binaryData
    }

    init(data: Data, modifiedDate: Date, mergeAsyncClosure: BinaryFileMergeClosure?) {
        self.modifiedDate = modifiedDate
        self.binaryData = data
        self.mergeAsyncClosure = mergeAsyncClosure
    }

    func shouldOverwrite(other: Self) -> Bool {
        return self.binaryData != other.binaryData &&
                self.modifiedDate > other.modifiedDate
    }

    func mergeAsync(with other: BinaryFileSyncable, merged: @escaping MergedClosure) {
        if let mergeAsyncClosure = self.mergeAsyncClosure {
            mergeAsyncClosure(self.binaryData, other.binaryData) { mergedData in
                let mergedItem = BinaryFileSyncable(data: mergedData, modifiedDate: Date(), mergeAsyncClosure: mergeAsyncClosure)
                merged(mergedItem)
            }
        } else if let mergeAsyncClosure = other.mergeAsyncClosure {
            mergeAsyncClosure(other.binaryData, self.binaryData) { mergedData in
                let mergedItem = BinaryFileSyncable(data: mergedData, modifiedDate: Date(), mergeAsyncClosure: mergeAsyncClosure)
                merged(mergedItem)
            }
        } else {
            merged(merge(with: other))
        }
    }

    static func == (lhs: BinaryFileSyncable, rhs: BinaryFileSyncable) -> Bool {
        return lhs.binaryData == rhs.binaryData
    }

}

internal extension BinaryFileSyncable {

    // for local copies of BinaryFileSyncable we only save and load the underlying data.
    // cloud copies include the whole struct
    static func internalDecodeFromLocal(fileURL: URL,
                                        compression: compression_algorithm?,
                                        binaryMerge: BinaryFileMergeClosure?) -> (decoded: Self?,
                                                                                  payloadData: Data?) {
        guard FileManager.default.fileExists(atPath: fileURL.path),
            let rawData = try? Data(contentsOf: fileURL) else {
                return (decoded: nil, payloadData: nil)
        }

        var modificationDate: Date
        do {
            let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modified = attr[.modificationDate] as? Date {
                modificationDate = modified
            } else if let created = attr[.creationDate] as? Date {
                modificationDate = created
            } else {
                DebugAssert(false, "Failed to get local file modifiation date for \(fileURL)")
                return (decoded: nil, payloadData: nil)
            }
        } catch {
            DebugAssert(false, "Failed to get local file modifiation date for \(fileURL)")
            return (decoded: nil, payloadData: nil)
        }

        var uncompressedData: Data
        if let compression = compression,
            let decompressed = rawData.decompress(algorithm: compression) {
            uncompressedData = decompressed
        } else {
            uncompressedData = rawData
        }

        let binaryFileSyncable = BinaryFileSyncable(data: uncompressedData,
                                                    modifiedDate: modificationDate,
                                                    mergeAsyncClosure: binaryMerge)

        let encoder = JSONEncoder()        

        guard let jsonData = try? encoder.encode(binaryFileSyncable) else {
            DebugAssert(false, "Failed to encode save state json for \(fileURL)")
            return (decoded: nil, payloadData: nil)
        }

        var payloadData: Data
        if let compression = compression,
            let zipData = jsonData.compress(algorithm: compression) {
            payloadData = zipData
        } else {
            payloadData = jsonData
        }

        return (decoded: binaryFileSyncable, payloadData: payloadData)
    }

    @discardableResult func internalSaveLocalTo(fileURL: URL,
                                                compression: compression_algorithm? = COMPRESSION_LZFSE) -> Data? {
        self.binaryData.write(toFileURL: fileURL, compression: compression)
        return self.compress(with: compression)
    }

    @discardableResult func internalWrite(uncompressedData: Data,
                                  toFileURL fileURL: URL,
                                  compression: compression_algorithm?) -> Data?  {
        self.binaryData.write(toFileURL: fileURL, compression: compression)
        return self.compress(with: compression)
    }

}
