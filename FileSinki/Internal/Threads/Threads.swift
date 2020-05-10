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
    DispatchQueue.global(qos: .default).async {
        block()
    }
}
