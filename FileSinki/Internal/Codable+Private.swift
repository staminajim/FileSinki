//
//  Codable+Compression.swift
//  LocoLooper
//
//  Created by James Van-As on 6/11/19.
//  Copyright © 2019 Fat Eel Studios. All rights reserved.
//

import Foundation
import Compression

internal extension Decodable {

    static func decodeFromLocal(fileURL: URL,
                                compression: compression_algorithm?,
                                binaryMerge: BinaryFileMergeClosure?) -> (decoded: Self?,
                                     payloadData: Data?) {
        if type(of: self) == type(of: BinaryFileSyncable.self) {
            return BinaryFileSyncable.internalDecodeFromLocal(fileURL: fileURL,
                                                              compression: compression,
                                                              binaryMerge: binaryMerge) as! (decoded: Self?, payloadData: Data?)
        } else {
            return self.internalDecodeFromLocal(fileURL: fileURL, compression: compression)
        }
    }

    static func internalDecodeFromLocal(fileURL: URL,
                                        compression: compression_algorithm?) -> (decoded: Self?,
                                                                         payloadData: Data?) {
        var localDecoded: Self?
        var localPayloadData: Data?

        if let compression = compression {
            let zipURL = fileURL.withCompressionSuffix(compression)
            let zipData = try? Data(contentsOf: zipURL)

            if let jsonData = zipData?.decompress(algorithm: compression),
                let decoded = try? JSONDecoder().decode(Self.self, from: jsonData) {
                localDecoded = decoded
                localPayloadData = zipData
            } else if let uncompressedData = try? Data(contentsOf: zipURL),
                    let decoded = try? JSONDecoder().decode(Self.self, from: uncompressedData) {
                // fallback for when compression fails (eg. tiny files)
                localDecoded = decoded
                localPayloadData = uncompressedData
            }
        } else if let uncompressedData = try? Data(contentsOf: fileURL),
                let decoded = try? JSONDecoder().decode(Self.self, from: uncompressedData) {
            localDecoded = decoded
            localPayloadData = uncompressedData
        }

        return (decoded: localDecoded, payloadData: localPayloadData)
    }

}

internal extension Encodable {

    @discardableResult func internalSaveLocalTo(fileURL: URL,
                                                compression: compression_algorithm? = COMPRESSION_LZFSE) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let jsonData = try? encoder.encode(self) else {
            DebugAssert(false, "Failed to encode save state json \(String(describing: self))")
            return nil
        }

        return jsonData.write(toFileURL: fileURL, compression: compression)
    }

    @discardableResult func write(uncompressedData: Data,
                                  toFileURL fileURL: URL,
                                  compression: compression_algorithm?) -> Data?  {
        if self is BinaryFileSyncable {
            return (self as! BinaryFileSyncable).internalWrite(uncompressedData: uncompressedData,
                                                               toFileURL: fileURL,
                                                               compression: compression)
        } else {
            return self.internalWrite(uncompressedData: uncompressedData,
                                      toFileURL: fileURL,
                                      compression: compression)
        }
    }

    @discardableResult func internalWrite(uncompressedData: Data,
                                  toFileURL fileURL: URL,
                                  compression: compression_algorithm?) -> Data?  {
        return uncompressedData.write(toFileURL: fileURL, compression: compression)
    }

}

