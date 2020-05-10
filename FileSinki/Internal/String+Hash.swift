//
//  String+Hash.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 16/04/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation

internal extension String {

    /// fast FNV-1a hash. https://en.wikipedia.org/wiki/Fowler–Noll–Vo_hash_function
    func fnvHash() -> String {
        let utf8Bytes = self.utf8
        var hash: UInt = 14695981039346656037
        let FNVPrime: UInt = 1099511628211
        for byte in utf8Bytes {
           hash ^= UInt(byte)
           hash = hash &* FNVPrime
        }
        return String(format:"%02x", hash)
    }

}
