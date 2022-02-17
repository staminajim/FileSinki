//
//  Logging.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 9/05/20.
//

import Foundation

func DebugLog(_ string:  @autoclosure () -> String) {
    #if DEBUG    
    print("FileSinki: " + string())
    #endif
}
