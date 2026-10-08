//
//  WebSocketManager.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/22/25.
//

import Foundation
import Starscream

// WebSocket message structure matching backend format
struct WebSocketMessage: Codable {
	let event: String
	let data: AnyCodable
}

// Helper to encode/decode Any types in JSON
struct AnyCodable: Codable {
	let value: Any

	init(_ value: Any) {
		self.value = value
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let string = try? container.decode(String.self) {
			value = string
		} else if let int = try? container.decode(Int.self) {
			value = int
		} else if let double = try? container.decode(Double.self) {
			value = double
		} else if let bool = try? container.decode(Bool.self) {
			value = bool
		} else if let dict = try? container.decode([String: AnyCodable].self) {
			value = dict.mapValues { $0.value }
		} else if let array = try? container.decode([AnyCodable].self) {
			value = array.map { $0.value }
		} else {
			value = NSNull()
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch value {
		case let string as String:
			try container.encode(string)
		case let int as Int:
			try container.encode(int)
		case let double as Double:
			try container.encode(double)
		case let bool as Bool:
			try container.encode(bool)
		case let dict as [String: Any]:
			try container.encode(dict.mapValues { AnyCodable($0) })
		case let array as [Any]:
			try container.encode(array.map { AnyCodable($0) })
		default:
			try container.encodeNil()
		}
	}
}

@Observable
@MainActor
final class SocketService: WebSocketDelegate {
	enum ConnectionBannerState: Equatable {
		case connected
		case reconnecting
	}
	static let shared = SocketService()

	@MainActor static var verbose = false

	private var socket: WebSocket?
	private(set) var isConnectedForSync = false
	var bannerState: ConnectionBannerState {
		isConnectedForSync ? .connected : .reconnecting
	}
	private var reconnectTask: Task<Void, Never>?
	private let reconnectDelay: TimeInterval = 3.0

	public private(set) var groupsModel: GroupModel!

	private init() {}

	func start(with groupsModel: GroupModel) {
		self.groupsModel = groupsModel

		// Prevent double-starting
		if socket != nil { return }

		connect()
	}

	/// Call from willEnterForeground to guarantee the socket is alive.
	func ensureConnected() {
		guard ConnectivityMonitor.shared.isOnline else { return }
		guard groupsModel != nil, !isConnectedForSync else { return }
		reconnectTask?.cancel()
		reconnectTask = nil
		resetSocketState()
		connect()
	}

	private func connect() {
		guard ConnectivityMonitor.shared.isOnline else {
			if Self.verbose { print("WebSocket: Offline, skipping connect") }
			return
		}

		Task {
			let activeGroupId = GroupModel.shared.getActiveGroupId()
			guard let activeGroupId, !activeGroupId.isEmpty else {
				if Self.verbose { print("WebSocket: No active group, skipping connect") }
				return
			}

			var urlComponents = URLComponents(
				url: AppConfig.webSocketURL, resolvingAgainstBaseURL: false)!
			urlComponents.queryItems = [URLQueryItem(name: "groups", value: activeGroupId)]

			guard let wsURL = urlComponents.url else { return }

			var request = URLRequest(url: wsURL)
			request.timeoutInterval = 5

			// Nil the old delegate before releasing the socket.
			// Without this, its dealloc-triggered .cancelled fires back into
			// didReceive, setting isConnectedForSync = false and kicking off another
			// reconnect — creating a churn loop that compounds over time.
			socket?.delegate = nil
			socket?.disconnect()
			socket = nil

			let ws = WebSocket(request: request)
			ws.delegate = self
			socket = ws
			ws.connect()

			if Self.verbose { print("WebSocket: Connecting...") }
		}
	}

	func disconnect() {
		reconnectTask?.cancel()
		reconnectTask = nil
		resetSocketState()
		if Self.verbose { print("WebSocket: Disconnected") }
	}

	func restart() {
		reconnectTask?.cancel()
		reconnectTask = nil
		resetSocketState()
		connect()
	}

	// MARK: - WebSocketDelegate

	nonisolated func didReceive(event: WebSocketEvent, client: WebSocketClient) {
		switch event {
		case .connected(let headers):
			Task { @MainActor in
				isConnectedForSync = true
				reconnectTask?.cancel()
				reconnectTask = nil
				SyncEngine.shared.syncIfNeeded()
				// Anything missed while disconnected is recovered here.
				try? await SyncEngine.shared.reconcile()
				if Self.verbose { print("WebSocket connected:", headers) }
			}

		case .disconnected(let reason, let code):
			Task { @MainActor in
				resetSocketState()
				if Self.verbose { print("WebSocket disconnected:", reason, "code:", code) }
				scheduleReconnect()
			}

		case .text(let text):
			Task { @MainActor in
				handleMessage(text)
			}

		case .binary(let data):
			Task { @MainActor in
				if let text = String(data: data, encoding: .utf8) {
					handleMessage(text)
				}
			}

		case .error(let error):
			Task { @MainActor in
				resetSocketState()
				if Self.verbose { print("WebSocket error:", error ?? "unknown error") }
				scheduleReconnect()
			}

		case .cancelled:
			Task { @MainActor in
				resetSocketState()
				if Self.verbose { print("WebSocket cancelled") }
				scheduleReconnect()
			}

		case .peerClosed:
			Task { @MainActor in
				resetSocketState()
				if Self.verbose { print("WebSocket peer closed") }
				scheduleReconnect()
			}

		default:
			break
		}
	}

	private func resetSocketState() {
		socket?.delegate = nil
		socket?.disconnect()
		socket = nil
		isConnectedForSync = false
	}

	// MARK: - Reconnect

	private func scheduleReconnect() {
		guard ConnectivityMonitor.shared.isOnline else {
			if Self.verbose { print("WebSocket: Offline, not scheduling reconnect") }
			return
		}
		guard reconnectTask == nil else { return }
		if Self.verbose { print("WebSocket: reconnecting in \(reconnectDelay)s...") }
		reconnectTask = Task {
			try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
			guard !Task.isCancelled else { return }
			reconnectTask = nil
			guard ConnectivityMonitor.shared.isOnline else {
				if Self.verbose { print("WebSocket: Still offline, skipping reconnect") }
				return
			}
			connect()
		}
	}

	// MARK: - Message Handling

	private func handleMessage(_ text: String) {
		guard let data = text.data(using: .utf8) else { return }

		do {
			let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
			handleEvent(message.event, payload: message.data.value)
		} catch {
			if Self.verbose { print("WebSocket decode error:", error, "message:", text) }
		}
	}

	private func handleEvent(_ event: String, payload: Any) {
		if Self.verbose { print("WebSocket event:", event) }

		switch event {
		case "connected":
			if Self.verbose { print("Server connected message:", payload) }

		// MARK: Group Events
		case "group_updated":
			decode(payload, as: AuthGroup.self) { group in
				if Self.verbose { print("group updated:", group) }
				self.groupsModel.updateGroup(group)
			}

		case "group_deleted":
			decode(payload, as: String.self) { groupID in
				if Self.verbose { print("group deleted:", groupID) }
				self.groupsModel.leaveGroup(id: groupID)
			}

		// MARK: Grocery Item Events
		case "grocery_item_created", "grocery_item_updated":
			decode(payload, as: GroceryItem.self) { item in
				if Self.verbose { print("grocery upsert:", item.id) }
				SyncEngine.shared.applyServerUpsert(item)
			}

		case "grocery_items_updated":
			decode(payload, as: [GroceryItem].self) { items in
				if Self.verbose { print("groceries upsert:", items.count) }
				items.forEach { SyncEngine.shared.applyServerUpsert($0) }
			}

		case "grocery_item_deleted":
			if let id = (payload as? [String: Any])?["id"] as? String, let uuid = UUID(uuidString: id) {
				SyncEngine.shared.applyServerDelete(type: .grocery, id: uuid)
			}

		// MARK: Meal Plan Events
		case "meal_plan_created", "meal_plan_updated":
			decode(payload, as: MealPlan.self) { meal in
				if Self.verbose { print("meal upsert:", meal.id) }
				SyncEngine.shared.applyServerUpsert(meal)
			}

		case "meal_plan_deleted":
			if let id = (payload as? [String: Any])?["id"] as? String, let uuid = UUID(uuidString: id) {
				SyncEngine.shared.applyServerDelete(type: .meal, id: uuid)
			}

		// MARK: Receipt Events
		case "receipt_created", "receipt_updated":
			decode(payload, as: Receipt.self) { receipt in
				if Self.verbose { print("receipt upsert:", receipt.id) }
				SyncEngine.shared.applyServerUpsert(receipt)
			}

		case "receipt_deleted":
			if let id = (payload as? [String: Any])?["id"] as? String, let uuid = UUID(uuidString: id) {
				SyncEngine.shared.applyServerDelete(type: .receipt, id: uuid)
			}

		default:
			if Self.verbose { print("Unknown event:", event) }
		}
	}

	private func decode<T: Decodable>(
		_ payload: Any, as type: T.Type, _ completion: (T) -> Void
	) {
		do {
			let jsonData = try JSONSerialization.data(withJSONObject: payload)
			let obj = try JSONDecoder().decode(T.self, from: jsonData)
			completion(obj)
		} catch {
			print("WebSocket decode error:", error, "payload:", payload)
		}
	}

	// MARK: - Send

	func send(event: String, data: [String: Any]) {
		guard isConnectedForSync else {
			if Self.verbose { print("WebSocket: Cannot send, not connected") }
			return
		}
		let message: [String: Any] = ["event": event, "data": data]
		do {
			let jsonData = try JSONSerialization.data(withJSONObject: message)
			if let jsonString = String(data: jsonData, encoding: .utf8) {
				socket?.write(string: jsonString)
				if Self.verbose { print("WebSocket sent:", event) }
			}
		} catch {
			if Self.verbose { print("WebSocket send error:", error) }
		}
	}
}
