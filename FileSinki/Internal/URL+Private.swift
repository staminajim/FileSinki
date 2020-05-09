//
//  URL+ItemKeys.swift
//  LocoLooper
//
//  Created by James Van-As on 2/05/20.
//  Copyright © 2020 Fat Eel Studios. All rights reserved.
//

import Foundation
import Compression

internal extension URL {

    func withCompressionSuffix(_ compressionAlgorithm: compression_algorithm?) -> URL {
        guard let compressionAlgorithm = compressionAlgorithm,
            let suffix = FileManager.archiveSuffix(compressionAlgorithm) else {
            return self
        }
        let filename = self.lastPathComponent
        let folderURL = self.deletingLastPathComponent()
        let existingFileExtension = self.pathExtension

        guard existingFileExtension != suffix else { return self }

        let zipFilename = filename.appending("." + suffix)
        return folderURL.appendingPathComponent(zipFilename)        
    }

    func hasCompressionSuffix() -> Bool {
        let path = self.path

        return path.hasSuffix("lzfse") || path.hasSuffix("zlib") ||
               path.hasSuffix("lz4") || path.hasSuffix("lzma")
    }

}

// MARK: Paths and URLs

internal extension URL {

    init(path: String, root: FileManager.SearchPathDirectory) {
        let rootFolderName = URL.localRootFolder(for: root).path + "/"
        if path.hasPrefix(rootFolderName) {
            // strip the path down if we happened to pass in a full file path
            let stripped = String(path.dropFirst(rootFolderName.count))
            self.init(fileURLWithPath: rootFolderName + stripped, isDirectory: path.last == "/")
        } else {
            self.init(fileURLWithPath: rootFolderName + path, isDirectory: path.last == "/")
        }
    }

    /// the file path, with pre-icloud portion stripped (eg. /User/Blaa/Application Support/com.blaa.LocoLooper/ is stripped)
    func cloudPath(for searchPathDirectory: FileManager.SearchPathDirectory) -> String? {
        let rootFolderName = URL.localRootFolder(for: searchPathDirectory).path + "/"
        guard self.path.hasPrefix(rootFolderName) else {
            DebugAssert(false, "\(self.path) was expected to be prefixed with \(rootFolderName)")
            return nil
        }
        let stripped = String(self.path.dropFirst(rootFolderName.count))

        if hasDirectoryPath {
            return stripped + "/"
        } else {
            return stripped
        }
    }

    /// The default application Support Folder, using the app bundle ID
    static func localRootFolder(for searchPathDirectory: FileManager.SearchPathDirectory) -> URL {
        if searchPathDirectory == .applicationSupportDirectory,
            let appSupportFolder = FileSinki.appSupportFolder {
            return appSupportFolder
        }
        
        let root: URL

        #if os(tvOS)
        guard let appFolder = FileManager.default.urls(for: .cachesDirectory,
                                            in: .userDomainMask).first else {
                                                fatalError("Error creating local application support folder")
        }
        // tvOS can only write to the caches directory
        let bundleID = Bundle.main.bundleIdentifier!
        let cacheRoot = appFolder.appendingPathComponent(bundleID, isDirectory: true)
        root = cacheRoot.appendingPathComponent("\(searchPathDirectory)", isDirectory: true)
        #else
        guard let appFolder = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first else {
                                                fatalError("Error creating local application support folder")

        }
        if searchPathDirectory == .applicationSupportDirectory {
            let bundleID = Bundle.main.bundleIdentifier!
            root = appFolder.appendingPathComponent(bundleID, isDirectory: true)
        } else {
            root = appFolder
        }
        #endif

        FileManager.default.createDirectoriesIfNecessary(for: root)

        if searchPathDirectory == .applicationSupportDirectory {
            FileSinki.appSupportFolder = root
        }

        return root
    }

}

internal extension String {

    func localURLFromCloudPath(for searchPathDirectory: FileManager.SearchPathDirectory) -> URL {
        return URL.localRootFolder(for: searchPathDirectory).appendingPathComponent(self)
    }

    func toRecordID(root: FileManager.SearchPathDirectory) -> String {
        return String.recordIDPrefix(for: root) + String.recordIDFrom(cloudPath: self)
    }

    func recordIDToLocalURL() -> URL? {
        let components = self.components(separatedBy: ":")
        guard let prefix = components.first, components.count > 1 else {
            DebugAssert(false, "Failed to extract searchPathDir from \(self)")
            return nil }
        let root = prefix.replacingOccurrences(of: "FS", with: "")
        guard let rootInt = UInt(root),
            let searchPathDir = FileManager.SearchPathDirectory(rawValue: rootInt) else {
                DebugAssert(false, "Failed to extract searchPathDir from \(self)")
                return nil
        }
        return URL(path: components[1], root: searchPathDir)
    }

    func recordIDWithFileSinkiPrefixRemoved() -> String {
        let components = self.components(separatedBy: ":")
        guard components.count > 1 else {
            return self
        }
        return components[1]
    }

    private static func recordIDPrefix(for searchPathDirectory: FileManager.SearchPathDirectory) -> String {
        return "FS\(searchPathDirectory.rawValue):"
    }

    private static func recordIDFrom(cloudPath: String) -> String {
        return cloudPath.count < 250 ? cloudPath : cloudPath.fnvHash()
    }

}
