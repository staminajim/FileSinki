//
//  Reachability.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 9/05/20.
//  Copyright © 2020 James Van-As. All rights reserved.
//

import Foundation

internal class ReachabilityManager {

    private let reachability: Reachability?

    init() {
        reachability = Reachability.forInternetConnection()
        reachability?.startNotifier()

        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged(_:)),
                                               name: .reachabilityChanged, object: nil)
    }

    private var permanentRetryOperations = [() -> ()]()

    private var retryOperations = [() -> ()]()

    func addRetryOperation(_ retry: @escaping () -> ()) {
        runOnMain {
            self.retryOperations.append(retry)
        }
    }

    func addPermanentRetryOperation(_ retry: @escaping () -> ()) {
        runOnMain {
            self.permanentRetryOperations.append(retry)
        }
    }

    @objc func reachabilityChanged(_ notification: Notification?) {
        if reachability?.status != .notReachable {
            runOnMain {
                self.runAllRetries()
            }
        }
    }

    private func runAllRetries() {
        for retry in permanentRetryOperations {
            retry()
        }

        let copy = retryOperations
        retryOperations.removeAll()
        for retry in copy {
            retry()
        }
    }

}
