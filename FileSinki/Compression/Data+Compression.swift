//
//  Data+Compression.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 15/04/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation
import Compression

public extension Data {

    /**
    Syncronously saves the data locally for a given local file URL

    - Parameter fileURL: Local file url to save to
    - Parameter compression: Which compression algorithm to use, if any.
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */
    @discardableResult func write(toFileURL fileURL: URL,
                                  compression: compression_algorithm?) -> Data?  {
        let zipFileURL = fileURL.withCompressionSuffix(compression)

        try? FileManager.default.createDirectory(atPath: zipFileURL.deletingLastPathComponent().path,
                                                 withIntermediateDirectories: true, attributes: nil)

        if let compression = compression,
            let zipData = self.compress(algorithm: compression) {
            do {
                try zipData.write(to: zipFileURL, options: .atomic)
                return zipData
            } catch let error {
                DebugAssert(false, "Failed to write data file to \(zipFileURL) \(error)")
                return nil
            }
        } else {
            do {
                try self.write(to: zipFileURL, options: .atomic)
                return self
            } catch let error {
                DebugAssert(false, "Failed to write data file to \(fileURL) \(error)")
                return nil
            }
        }
    }
    
    /**
    Compresses the data with the given compression algorithm

    - Parameter algorithm: Compression algorithm to be used.
    - Returns: A compressed Data object. nil if compression did not succeed.
    */
    func compress(algorithm: compression_algorithm) -> Data? {
        let inputDataSize = self.count
        let byteSize = MemoryLayout<UInt8>.stride
        let bufferSize = inputDataSize / byteSize
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)

        var sourceBuffer = Array<UInt8>(repeating: 0, count: bufferSize)
        self.copyBytes(to: &sourceBuffer, count: inputDataSize)

        let compressedSize = compression_encode_buffer(destinationBuffer,
                                                        inputDataSize,
                                                        &sourceBuffer,
                                                        inputDataSize,
                                                        nil,
                                                        algorithm)
        guard compressedSize > 0 else {
            // can return 0 if trying to compress something very small
            return nil
        }
        return NSData(bytesNoCopy: destinationBuffer, length: compressedSize) as Data
    }

    /**
    Decompresses the data with the given compression algorithm

    - Parameter algorithm: Compression algorithm to be used.
    - Returns: A decompressed Data object. nil if compression did not succeed.
    */
    func decompress(algorithm: compression_algorithm) -> Data? {
        guard self.count > 0 else {
            DebugAssert(false, "Failed to decompress data \(self). Data was empty.")
            return nil
        }

        // This is all based on apple's doc example code. So it might work sometimes.
        var compressionStream: compression_stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1).pointee
        defer {
            compression_stream_destroy(&compressionStream)
        }

        var status = compression_stream_init(&compressionStream, COMPRESSION_STREAM_DECODE, algorithm)
        guard status != COMPRESSION_STATUS_ERROR else {
            DebugAssert(false, "Failed to decompress data \(self). Data was empty.")
            return nil
        }

        let outputData = self.withUnsafeBytes {  ptr -> Data in
            let bytes = ptr.bindMemory(to: UInt8.self).baseAddress!

            compressionStream.src_ptr = bytes
            compressionStream.src_size = self.count

            status = compression_stream_process(&compressionStream, 0)

            let dstBufferSize : size_t = 32768
            let destinationBufferPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: dstBufferSize)
            defer {
                destinationBufferPtr.deallocate()
            }
            compressionStream.dst_ptr = destinationBufferPtr
            compressionStream.dst_size = dstBufferSize

            var outputData = Data()

            repeat {
                status = compression_stream_process(&compressionStream, 0)

                switch status {
                case COMPRESSION_STATUS_OK:
                    if compressionStream.dst_size == 0 {
                        // destination buffer is full, move back to beginning
                        outputData.append(destinationBufferPtr, count: dstBufferSize)
                        compressionStream.dst_ptr = destinationBufferPtr
                        compressionStream.dst_size = dstBufferSize
                    }
                case COMPRESSION_STATUS_END:
                    if compressionStream.dst_ptr > destinationBufferPtr {
                        outputData.append(destinationBufferPtr,
                                          count: compressionStream.dst_ptr - destinationBufferPtr)
                    }
                case COMPRESSION_STATUS_ERROR:
                    // DebugLog("Failed to decompress data \(self). A decompression error occurred.")
                    // this can error out on tiny files. In which case we treat as non compressed
                    return Data()
                default:
                    break
                }

            } while status == COMPRESSION_STATUS_OK

            return outputData
        }

        return outputData.count > 0 ? outputData : nil
    }

}
