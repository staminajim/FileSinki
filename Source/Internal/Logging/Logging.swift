//
//  Logging.swift
//  FileSinki
//
//  Created by James Van-As on 9/05/20.
//

import Foundation

func DebugLog(_ string: String) {
    #if DEBUG
    print("FileSinki: " + string)
    #endif
}
