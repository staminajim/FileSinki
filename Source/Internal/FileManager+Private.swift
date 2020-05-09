//
//  FileManager.swift
//  LocoLooper
//
//  Created by James Van-As on 15/04/20.
//  Copyright © 2020 Fat Eel Studios. All rights reserved.
//

import Foundation
import Compression

internal extension FileManager {

    // MARK: - Compression File Extensions

    static func archiveSuffix(_ compressionAlgorithm: compression_algorithm) -> String? {
        switch compressionAlgorithm {
        case COMPRESSION_LZ4:
            return "lz4"
        case COMPRESSION_ZLIB:
            return "zlib"
        case COMPRESSION_LZMA:
            return "lzma"
        case COMPRESSION_LZFSE:
            return "lzfse"
        default:
            return nil
        }
    }

    static func compressionAlgorithm(archiveSuffix: String) -> compression_algorithm? {
        switch archiveSuffix.lowercased() {
        case "lz4":
            return COMPRESSION_LZ4
        case "zlib":
            return COMPRESSION_ZLIB
        case "lzma":
            return COMPRESSION_LZMA
        case "lzfse":
            return COMPRESSION_LZFSE
        default:
            return nil
        }
    }

    // MARK: - Creating Folders

    func createDirectoriesIfNecessary(for directoryURL: URL) {
        var isDirectory: ObjCBool = false        
        let folderExists = FileManager.default.fileExists(atPath: directoryURL.path,
                                                          isDirectory: &isDirectory)
        if !folderExists || !isDirectory.boolValue {
            do {
                try FileManager.default.createDirectory(at: directoryURL,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            } catch let error {
                fatalError("Error creating folder \(directoryURL): \(error)")
            }
        }
    }

}
