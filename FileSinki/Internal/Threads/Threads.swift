//
//  Threads.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 9/05/20.
//

import Foundation

func runOnMain(block: @escaping () -> ()) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.async(execute: block)
    }
}

func runAsync(block: @escaping () -> ()) {
    let operation = BlockOperation {
        block()
    }
    operation.qualityOfService = .userInitiated
    Scheduler.asyncQueue.addOperation(operation)
}

fileprivate final class Scheduler {

    static let asyncQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "filesinki_async"
        queue.maxConcurrentOperationCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        return queue
    }()

}
