//
//  Codable+FileCompression.swift
//  LocoLooper
//
//  Created by James Van-As on 6/11/19.
//  Copyright © 2019 Fat Eel Studios. All rights reserved.
//

import Foundation
import Compression

// MARK: - Local Saving and loading

extension Encodable {

    /**
    Syncronously saves the Encodable item locally for a given local file URL

    - Parameter fileURL: Local file url to save to
    - Parameter compression: Which compression algorithm to use, if any. Defaults to zlib.
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */

    @discardableResult func saveLocalTo(fileURL: URL,
                                        compression: compression_algorithm?) -> Data? {
        if self is BinaryFileSyncable {
            return (self as! BinaryFileSyncable).internalSaveLocalTo(fileURL: fileURL, compression: compression)
        } else {
            return internalSaveLocalTo(fileURL: fileURL, compression: compression)
        }
    }

    /**
    Syncronously compresses the Encodable item and returns the encoded Data

    - Parameter with compression: Which compression algorithm to use
    - Returns: The encoded Data. nil if did not succeed. Can sometimes return uncompressed Data if item is tiny.
    */
    func compress(with compression: compression_algorithm?) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let jsonData = try? encoder.encode(self) else {
            DebugAssert(false, "Failed to encode save state json \(String(describing: self))")
            return nil
        }
        if let compression = compression {
            return jsonData.compress(algorithm: compression) ?? jsonData
        } else {
            return jsonData
        }
    }

}

internal extension Decodable {

    /**
    Syncronously loads the local copy of Decodable item for a given local file URL

    - Parameter fileURL: Local file url of the decodable item.
    - Parameter compression: Which compression algorithm to use, if any. Defaults to zlib.
    - Returns: A decoded item from the local store. nil if did not succeed.
    */
    static func loadFromLocal(fileURL: URL,
                              compression: compression_algorithm? = COMPRESSION_LZFSE) -> Self? {
        return decodeFromLocal(fileURL: fileURL, compression: compression, binaryMerge: nil).decoded
    }

    /**
    Syncronously decompresses the Encodable item and returns the encoded Data

    - Parameter data: Compressed data to decode
    - Parameter compression: Which compression algorithm to use
    - Returns: The decompressed Decodable. nil if did not succeed.
    */
    static func decodeFrom(data: Data, compression: compression_algorithm) -> Self? {
        if let decompressedData = data.decompress(algorithm: compression) {
            return try? JSONDecoder().decode(Self.self, from: decompressedData)
        } else {    // fallback try and just straight up decode it
            return try? JSONDecoder().decode(Self.self, from: data)
        }
    }

}

