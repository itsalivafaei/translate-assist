//
//  Reachability.swift
//  translate assist
//
//  Phase 10: NWPathMonitor-based reachability to surface offline state proactively.
//

import Foundation
import Network

public final class NetworkReachability {
    public static let shared = NetworkReachability()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.translateassist.reachability")
    private(set) public var isOnline: Bool = true

    private init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let online = (path.status == .satisfied)
            if online != self.isOnline {
                self.isOnline = online
                NotificationCenter.default.post(name: .networkReachabilityChanged, object: online)
            } else {
                self.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }
}

public extension Notification.Name {
    static let networkReachabilityChanged = Notification.Name("network.reachability.changed")
}


