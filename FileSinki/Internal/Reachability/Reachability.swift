//
//  Reachability.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 10/05/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//
//  See LICENSE 
//

import Foundation
import SystemConfiguration

internal extension Notification.Name {
    static let reachabilityChanged = Notification.Name("JVReachabilityChanged")
}

/// This is a slimmed down interpretation of apple's reachability example code in swift
internal class Reachability {

    enum Status {
        case notReachable
        case reachableViaWifi
        case reachableViaWWAN
    }

    let scReachability: SCNetworkReachability

    let socketAddress: sockaddr

    // MARK: - Init

    init(scReachability: SCNetworkReachability, socketAddress: inout sockaddr) {
        self.scReachability = scReachability
        self.socketAddress = socketAddress
    }

    static func forInternetConnection() -> Reachability? {
        var zeroAddress = sockaddr()
        zeroAddress.sa_len = UInt8(MemoryLayout<sockaddr>.size)
        zeroAddress.sa_family = sa_family_t(AF_INET)

        guard let scReachability = SCNetworkReachabilityCreateWithAddress(nil, &zeroAddress) else {
           DebugAssert(false, "Failed to create network reachability manager")
           return nil
        }

        return Reachability(scReachability: scReachability, socketAddress: &zeroAddress)
    }

    // MARK: - Deinit

    deinit {
        stopNotifier()
    }

    // MARK: - Registering For Notifications

    static let callback: SCNetworkReachabilityCallBack = { (target, flags, info) in
        runOnMain {
            NotificationCenter.default.post(name: .reachabilityChanged, object: nil)
        }
    }

    @discardableResult func startNotifier() -> Bool {
        var context = SCNetworkReachabilityContext(version: 0,
                                                   info: nil,
                                                   retain: nil,
                                                   release: nil,
                                                   copyDescription: nil)

        guard SCNetworkReachabilitySetCallback(scReachability, Reachability.callback, &context) else { return false }
        return SCNetworkReachabilityScheduleWithRunLoop(scReachability, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    @discardableResult func stopNotifier() -> Bool {
        SCNetworkReachabilityUnscheduleFromRunLoop(scReachability,  CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    // MARK: - Status

    var status: Status {
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(scReachability, &flags) else {
            return .notReachable
        }
        return networkStatusForFlags(flags)
    }

    private func networkStatusForFlags(_ flags: SCNetworkReachabilityFlags) -> Status {
        if !flags.contains(.reachable) {
            return .notReachable
        }
        if !flags.contains(.connectionRequired) {
            // If the target host is reachable and no connection is required then we'll assume (for now) that you're on Wi-Fi...
            return .reachableViaWifi
        }
        if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
            // if the connection is on-demand (or on-traffic) if the calling application is using the CFSocketStream or higher APIs...
            if !flags.contains(.interventionRequired) {
                return .reachableViaWifi
            }
        }

        #if os(iOS)
        if flags.contains(.isWWAN) {
            return .reachableViaWWAN
        }
        #endif

        return .notReachable
    }

}
