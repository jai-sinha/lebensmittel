//
//  ConnectivityMonitor.swift
//  lebensmittel
//
//  Created by Jai Sinha on 3/25/26.
//

import Foundation
import Network

/// Observable singleton wrapping NWPathMonitor, and publishing isOnline
@Observable
@MainActor
final class ConnectivityMonitor {
	static let shared = ConnectivityMonitor()

	/// true when the device has a usable network path.
	private(set) var isOnline: Bool = true

	private let monitor = NWPathMonitor()
	private let monitorQueue = DispatchQueue(label: "com.lebensmittel.connectivity", qos: .utility)

	private init() {
		monitor.pathUpdateHandler = { [weak self] path in
			let satisfied = path.status == .satisfied
			Task { @MainActor [weak self] in
				self?.isOnline = satisfied
			}
		}
		monitor.start(queue: monitorQueue)
		// seed initial state from the current path (available after start)
		isOnline = monitor.currentPath.status == .satisfied
	}

	deinit {
		monitor.cancel()
	}
}
