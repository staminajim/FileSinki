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

public class FileSinki {
    
    internal static var cloudKitManager: CloudKitManager!
    internal static let localDB = LocalDatabase()
    internal static var observerManager: ObserverManager!
    internal static var appSupportFolder: URL?
    internal static let reachability = ReachabilityManager()

    // MARK: - Changed Closures

    public typealias GenericChanged = ((_ changedItems: [ChangeItemGeneric]) -> Void)

    public struct ChangeItemGeneric {
        public let localURL: URL
        public let path: String
    }

    public struct ChangeItem<T: FileSyncable> {
        public let item: T
        public let localURL: URL
        public let path: String
        
        public typealias Changed = ((_ changedItem: FileSinki.ChangeItem<T>) -> Void)
    }

}
