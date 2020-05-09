//
//  FileSinki+Private.swift
//  LocoLooper
//
//  Created by James Van-As on 7/05/20.
//  Copyright © 2020 Fat Eel Studios. All rights reserved.
//

import Foundation

class FileSinki {
    
    internal static var cloudKitManager: CloudKitManager!
    internal static let localDB = LocalDatabase()
    internal static var observerManager: ObserverManager!
    internal static var appSupportFolder: URL?
    internal static let reachability = ReachabilityManager()

    // MARK: - Changed Closures

    typealias GenericChanged = ((_ changedItems: [ChangeItemGeneric]) -> Void)

    struct ChangeItemGeneric {
        let localURL: URL
        let path: String
    }

    struct ChangeItem<T: FileSyncable> {
        let item: T
        let localURL: URL
        let path: String
        
        typealias Changed = ((_ changedItem: FileSinki.ChangeItem<T>) -> Void)
    }

}
