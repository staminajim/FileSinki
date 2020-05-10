//
//  Assert.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 9/05/20.
//

import Foundation

func DebugAssert(_ condition: Bool,
                 _ message: String,
                 file: StaticString = #file,
                 function: StaticString = #function,
                 line: Int = #line) {
    #if DEBUG
    if (!condition) {
        print("FileSinki Assert Failed: " + message)
        if (isBeingDebugged()) {
            kill (getpid(), SIGSTOP);
        } else {
            print("Could not break into debugger.");
        }
    }
    #else
    // do nothing
    #endif
}

func isBeingDebugged() -> Bool {
    var info = kinfo_proc()
    var mib : [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    assert(junk == 0, "sysctl failed")
    return (info.kp_proc.p_flag & P_TRACED) != 0
}
