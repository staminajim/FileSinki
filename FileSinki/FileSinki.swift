//
//  FileSinki
//
//  See LICENSE file for licensing information.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 3/05/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation
import Compression

// MARK: - FileSinki Setup

@objc public extension FileSinki {

    /**
       Initializes FileSinki. Call in AppDelegate didFinishLaunching with your CloudKit Container ID

       - Parameter cloudKitContainer: Your app's CloudKit Container ID.

       Note that by default Mac CloudKit Container IDs match with iOS / tvOS, so you need to specify the exact ID.
    */
    @objc static func setup(cloudKitContainer: String) {
        cloudKitManager = CloudKitManager(cloudKitContainer: cloudKitContainer, localDB: localDB)
        observerManager = ObserverManager(cloudKitManager: cloudKitManager, localDB: localDB)
    }

    /**
       Call FileSinki.didBecomeActive() in applicationDidBecomeActive in your AppDelegate to sync updates that happened while in the background
    */
    @objc static func didBecomeActive() {
         FileSinki.observerManager.didBecomeActive()
    }

    /**
       Call FileSinki.receivedNotification(userInfo) in didReceiveRemoteNotification in your AppDelegate to sync live updates

       - Parameter notificationPayload: The didReceiveRemoteNotification `userInfo: [String : Any]` payload received in AppDelegate
    */
    @objc static func receivedNotification(_ notificationPayload: [AnyHashable : Any]) {
         FileSinki.observerManager.receivedNotification(notificationPayload)
    }

}

// MARK: - Loading and Saving FileSyncables

public extension FileSinki {

    // MARK: Uncompressed
    /**
    Saves the FileSyncable item locally for a given local file URL, and also saves to the Cloud

    - Parameter item: Item to save
    - Parameter toPath: local path of the item, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter finalVersion: If the final version saved to the cloud is different to the one passed in (due to a merge or better available version)
     the final version is passed to this closure
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */
    @discardableResult static func save<T>(_ item: T,
                                           toPath path: String,
                                           root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                                           finalVersion: @escaping (_ item: T) -> ()) -> Data? where T: FileSyncable {
        return item.saveTo(fileURL: URL(path: path, root: root),
                           searchPathDirectory: root,
                           saveToCloud: true,
                           compression: nil,
                           finalVersion: finalVersion)
    }

    /**
    Loads the FileSyncable item locally for a given local relative file path, and also loads from the Cloud.

    - Parameter fileSyncable: The Type of the FileSyncable to load
    - Parameter fromPath: local path of the item, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter loaded: The Decoded item. nil if no item has been successfully decoded.

     Note: The loaded completion can be called multple times as data loads in from disk or the cloud,
     with the most up to date copy of the Decodable being returned last.
    */
    static func load<T>(_ fileSyncable: T.Type,
                        fromPath path: String,
                        root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                        loaded: @escaping (_ item: T?, _ wasRemote: Bool) -> ()) where T: FileSyncable {
        fileSyncable.loadFrom(fileURL: URL(path: path, root: root),
                              searchPathDirectory: root,
                              loadFromCloud: true,
                              compression: nil,
                              binaryMerge: nil,
                              loaded: loaded)
    }

    /**
       Deletes the FileSyncable locally for a given local file URL, and also saves the deletion to the Cloud

       - Parameter item: The item to delete
       - Parameter at: local path of the item, relative to the root
       - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    */
    static func delete<T>(_ item: T,
                          at path: String,
                          root: FileManager.SearchPathDirectory = .applicationSupportDirectory) where T: FileSyncable {
       item.delete(fileURL: URL(path: path, root: root),
                   searchPathDirectory: root,
                   saveToCloud: true)
    }

    // MARK: Compressed
    /**
    Compressed as Saves the FileSyncable item locally for a given local relative file path, and also saves to the Cloud

    - Parameter item: Item to save
    - Parameter toPath: local path of the item, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter finalVersion: If the final version saved to the cloud is different to the one passed in (due to a merge or better available version)
     the final version is passed to this closure
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */
    @discardableResult static func saveCompressed<T>(_ item: T,
                                                     toPath path: String,
                                                     root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                                                     finalVersion: @escaping (_ item: T) -> ()) -> Data? where T: FileSyncable {
        return item.saveTo(fileURL: URL(path: path, root: root),
                           searchPathDirectory: root,
                           saveToCloud: true,
                           compression: COMPRESSION_LZFSE,
                           finalVersion: finalVersion)
    }

    /**
    Loads the compressed FileSyncable item locally for a given local relative file path, and also loads from the Cloud.

    - Parameter fileSyncable: The Type of the FileSyncable to load
    - Parameter fromPath: local path of the item, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter loaded: The Decoded item. nil if no item has been successfully decoded.

     Note: The loaded completion can be called multple times as data loads in from disk or the cloud,
     with the most up to date copy of the Decodable being returned last.
    */
    static func loadCompressed<T>(_ fileSyncable: T.Type,
                                  fromPath path: String,
                                  root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                                  loaded: @escaping (_ item: T?, _ wasRemote: Bool) -> ()) where T: FileSyncable {
        fileSyncable.loadFrom(fileURL: URL(path: path, root: root),
                              searchPathDirectory: root,
                              loadFromCloud: true,
                              compression: COMPRESSION_LZFSE,
                              binaryMerge: nil,
                              loaded: loaded)
    }

    /**
       Deletes the compressed FileSyncable locally for a given local file URL, and also saves the deletion to the Cloud

       - Parameter item: The item to delete
       - Parameter at: local path of the item, relative to the root
       - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    */
    static func deleteCompressed<T>(_ item: T,
                                    at path: String,
                                    root: FileManager.SearchPathDirectory = .applicationSupportDirectory) where T: FileSyncable {
       item.delete(fileURL: URL(path: path, root: root),
                   searchPathDirectory: root,
                   saveToCloud: true,
                   compression: COMPRESSION_LZFSE)
    }

}

// MARK: - Loading and Saving Binary Files

@objc public extension FileSinki {

    // MARK: Uncompressed
    /**
    Saves the data item locally for a given local file URL, and also saves to the Cloud

    - Parameter data: binary data to save
    - Parameter path: local path of the item, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter mergeAsync: call merged() with the final merged Data to be used / saved to disk and the cloud
    - Parameter finalVersion: If the final version saved to the cloud is different to the one passed in (due to a merge or better available version)
     the final version is passed to this closure
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */
    @discardableResult static func saveBinaryFile(_ data: Data,
                                                  toPath path: String,
                                                  root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                                                  mergeAsync: @escaping BinaryFileMergeClosure,
                                                  finalVersion: @escaping (_ data: Data) -> ()) -> Data? {
        let binarySyncable = BinaryFileSyncable(data: data,
                                                modifiedDate: Date(),
                                                mergeAsyncClosure: mergeAsync)
        return binarySyncable.saveTo(fileURL: URL(path: path, root: root),
                                     searchPathDirectory: root,
                                     saveToCloud: true,
                                     compression: nil,
                                     finalVersion: { finalVersion($0.binaryData) } )
    }

    /**
    Loads the data item locally for a given local relative file path, and also loads from the Cloud.

    - Parameter path: local path of the data, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter mergeAsync: call merged() with the final merged Data to be used / saved to disk and the cloud
    - Parameter loaded: The Decoded data. nil if no item has been successfully decoded.

     Note: The loaded completion can be called multple times as data loads in from disk or the cloud,
     with the most up to date copy of the Decodable being returned last.
    */
    static func loadBinaryFile(fromPath path: String,
                               root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                               mergeAsync: @escaping BinaryFileMergeClosure,
                               loaded: @escaping (_ data: Data?, _ wasRemote: Bool) -> ()) {
        BinaryFileSyncable.loadFrom(fileURL: URL(path: path, root: root),
                                    searchPathDirectory: root,
                                    loadFromCloud: true,
                                    compression: nil,
                                    binaryMerge: mergeAsync) { binaryFileSyncable, wasRemote in
                        loaded(binaryFileSyncable?.binaryData, wasRemote)
        }
    }

    /**
       Deletes the FileSyncable locally for a given local file URL, and also saves the deletion to the Cloud

       - Parameter data: The item to delete
       - Parameter path: local path of the item, relative to the root
       - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    */
    static func deleteBinaryFile(data: Data,
                                 at path: String,
                                 root: FileManager.SearchPathDirectory = .applicationSupportDirectory) {
        let binarySyncable = BinaryFileSyncable(data: data, modifiedDate: Date(), mergeAsyncClosure: nil)
        FileSinki.delete(binarySyncable, at: path, root: root)
    }

    // MARK: Compressed
    /**
    Compressed as Saves the data item locally for a given local relative file path, and also saves to the Cloud

    - Parameter data: data to save
    - Parameter path: local path of the item, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter mergeAsync: call merged() with the final merged Data to be used / saved to disk and the cloud
    - Parameter finalVersion: If the final version saved to the cloud is different to the one passed in (due to a merge or better available version)
     the final version is passed to this closure
    - Returns: The encoded Data which has saved to disk. nil if did not succeed.
    */
    @discardableResult static func saveBinaryFileCompressed(_ data: Data,
                                         toPath path: String,
                                         root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                                         mergeAsync: BinaryFileMergeClosure?,
                                         finalVersion: @escaping (_ data: Data) -> ()) -> Data? {
        let binarySyncable = BinaryFileSyncable(data: data,
                                                modifiedDate: Date(),
                                                mergeAsyncClosure: mergeAsync)
        return binarySyncable.saveTo(fileURL: URL(path: path, root: root),
                                     searchPathDirectory: root,
                                     saveToCloud: true,
                                     compression: COMPRESSION_LZFSE,
                                     finalVersion: { finalVersion($0.binaryData) } )
    }

    /**
    Loads the compressed data item locally for a given local relative file path, and also loads from the Cloud.

    - Parameter path: local path of the item, relative to the root
    - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    - Parameter mergeAsync: call merged() with the final merged Data to be used / saved to disk and the cloud
    - Parameter loaded: The Decoded item. nil if no item has been successfully decoded.

     Note: The loaded completion can be called multple times as data loads in from disk or the cloud,
     with the most up to date copy of the Decodable being returned last.
    */
    static func loadBinaryFileCompressed(fromPath path: String,
                                         root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                                         mergeAsync: BinaryFileMergeClosure? = nil,
                                         loaded: @escaping (_ data: Data?, _ wasRemote: Bool) -> ()) {
        BinaryFileSyncable.loadFrom(fileURL: URL(path: path, root: root),
                                    searchPathDirectory: root,
                                    loadFromCloud: true,
                                    compression: COMPRESSION_LZFSE,
                                    binaryMerge: mergeAsync) { binaryFileSyncable, wasRemote in
                        loaded(binaryFileSyncable?.binaryData, wasRemote)
        }
    }

    /**
       Deletes the compressed data locally for a given local file URL, and also saves the deletion to the Cloud

       - Parameter data: The data to delete
       - Parameter path: local path of the item, relative to the root
       - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
    */
    static func deleteBinaryFileCompressed(_ data: Data,
                                           at path: String,
                                           root: FileManager.SearchPathDirectory = .applicationSupportDirectory) {
        let binarySyncable = BinaryFileSyncable(data: data, modifiedDate: Date(), mergeAsyncClosure: nil)
        FileSinki.deleteCompressed(binarySyncable, at: path, root: root)
    }

}

// MARK: - Observing Changes

public extension FileSinki {

    /**
       Observes remote changes to the given path. If the path is a folder, (ending in trailing "/") any files in that folder
        will be observed. If the path is not a folder, only changes to the specific file path will be observed.

       - Parameter observer: The object which wishes to observe the FileSinki changes.
       - Parameter for fileSyncableType: The FileSyncable type to observe changes for
       - Parameter path: The FileSinki path to oberve. eg "DataFolder/somefile.json" or "DataFolder/"
       - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
       - Parameter itemsChanged: Closure which is called any time remote changes to the given path occur
    */
    static func addObserver<T: FileSyncable>(_ observer: AnyObject,
                                             for fileSyncableType: T.Type,
                                             path: String,
                                             root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                                             itemsChanged: @escaping FileSinki.ChangeItem<T>.Changed) {
        FileSinki.observerManager.addObserver(self, fileSyncableType: fileSyncableType,
                                              path: path, root: root, onChange: itemsChanged)
    }

}

@objc public extension FileSinki {

    /**
       Observes remote changes to the given path. If the path is a folder, (ending in trailing "/") any files in that folder
        will be observed. If the path is not a folder, only changes to the specific file path will be observed.

        When receiveing the local urls which have changed, For each item you can then decide to load new copies etc etc

       - Parameter observer: The object which wishes to observe the FileSinki changes.
       - Parameter path: The FileSinki path to oberve. eg "DataFolder/somefile.json" or "DataFolder/"
       - Parameter root: The root search path directory. Defaults to .applicationSupportDirectory + bundle name
       - Parameter itemsChanged: Closure which is called any time remote changes to the given path occur
    */
    static func addObserver(_ observer: AnyObject,
                            path: String,
                            root: FileManager.SearchPathDirectory = .applicationSupportDirectory,
                            itemsChanged: @escaping FileSinki.GenericChanged) {
        FileSinki.observerManager.addObserver(self, path: path, root: root, onChange: itemsChanged)
    }

}

// MARK: - Root Folder

@objc public extension FileSinki {

    /// The default local root folder that FileSinki will use. Application Support/com.blaa.app/ on iOS and OSX, and Cache//com.blaa.app/ on tvOS
    static var defaultRootFolder: URL {
        return URL.localRootFolder(for: .applicationSupportDirectory)
    }

}

// MARK: - CloudKit Operation Queue

private let cloudKitDispatchQueue = DispatchQueue(label: "FileSinki.iCloud", qos: .userInitiated)

public extension FileSinki {

    static var cloudOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "FileSinki.iCloud"
        queue.underlyingQueue = cloudKitDispatchQueue
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

}
