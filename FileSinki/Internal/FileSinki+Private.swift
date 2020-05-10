//
//  FileSinki
//
//  See LICENSE file for licensing information+Private.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 7/05/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation

@objc public class FileSinki: NSObject {
    
    internal static var cloudKitManager: CloudKitManager!
    internal static let localDB = LocalDatabase()
    internal static var observerManager: ObserverManager!
    internal static var appSupportFolder: URL?
    internal static let reachability = ReachabilityManager()

    // MARK: - Changed Closures

    public typealias GenericChanged = ((_ changedItems: [ChangeItemGeneric]) -> Void)

    @objc(ChangeItem) public class ChangeItemGeneric: NSObject {
        @objc public let localURL: URL
        @objc public let path: String

        init(localURL: URL, path: String) {
            self.localURL = localURL
            self.path = path
        }
    }

    public struct ChangeItem<T: FileSyncable> {
        public let item: T
        public let localURL: URL
        public let path: String
        
        public typealias Changed = ((_ changedItem: FileSinki.ChangeItem<T>) -> Void)
    }

}
