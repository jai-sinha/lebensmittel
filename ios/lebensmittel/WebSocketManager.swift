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

	public private(set) var groceriesModel: GroceriesModel!
	public private(set) var shoppingModel: ShoppingModel!
	public private(set) var mealsModel: MealsModel!
	public private(set) var receiptsModel: ReceiptsModel!

	private init() {}

	func start(
		with groceriesModel: GroceriesModel,
		mealsModel: MealsModel,
		receiptsModel: ReceiptsModel,
		shoppingModel: ShoppingModel
	) {
		self.groceriesModel = groceriesModel
		self.mealsModel = mealsModel
		self.receiptsModel = receiptsModel
		self.shoppingModel = shoppingModel

		// Prevent double-starting
		if socket != nil { return }

		connect()
	}

	/// Call from willEnterForeground to guarantee the socket is alive.
	func ensureConnected() {
		guard ConnectivityMonitor.shared.isOnline else { return }
		guard groceriesModel != nil, !isConnectedForSync else { return }
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
			do {
				let token = try await AuthManager.shared.accessToken()
				let activeGroupId = try? await GroupService.shared.getActiveGroupId()

				var urlComponents = URLComponents(
					url: AppConfig.webSocketURL, resolvingAgainstBaseURL: false)!
				var queryItems = [URLQueryItem(name: "token", value: token)]
				if let activeGroupId, !activeGroupId.isEmpty {
					queryItems.append(URLQueryItem(name: "groups", value: activeGroupId))
				}
				urlComponents.queryItems = queryItems

				guard let wsURL = urlComponents.url else { return }

				var request = URLRequest(url: wsURL)
				request.timeoutInterval = 5
				request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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
			} catch {
				if Self.verbose { print("WebSocket: Failed to get auth token: \(error)") }
				scheduleReconnect()
			}
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

		// MARK: Grocery Item Events
		case "grocery_item_created":
			decode(payload, as: GroceryItem.self) { item in
				if Self.verbose { print("grocery created:", item) }
				guard !SyncEngine.shared.hasPendingOperation(serverID: item.id) else {
					if Self.verbose {
						print("Skipping grocery create for pending entity:", item.id)
					}
					return
				}
				self.groceriesModel.addItem(item)
			}

		case "grocery_item_updated":
			decode(payload, as: GroceryItem.self) { item in
				if Self.verbose { print("grocery updated:", item) }
				guard !SyncEngine.shared.hasPendingOperation(serverID: item.id) else {
					if Self.verbose {
						print("Skipping grocery update for pending entity:", item.id)
					}
					return
				}
				self.groceriesModel.updateItem(item)
			}

		case "grocery_items_updated":
			decode(payload, as: [GroceryItem].self) { items in
				if Self.verbose { print("groceries updated:", items) }
				for item in items {
					guard !SyncEngine.shared.hasPendingOperation(serverID: item.id) else {
						if Self.verbose {
							print("Skipping grocery batch update for pending entity:", item.id)
						}
						continue
					}
					self.groceriesModel.updateItem(item)
				}
			}

		case "grocery_item_deleted":
			if let dict = payload as? [String: Any], let id = dict["id"] as? String {
				guard !SyncEngine.shared.hasPendingOperation(serverID: id) else {
					if Self.verbose { print("Skipping grocery delete for pending entity:", id) }
					return
				}
				self.groceriesModel.removeItem(withId: id)
			}

		// MARK: Meal Plan Events
		case "meal_plan_created":
			decode(payload, as: MealPlan.self) { meal in
				if Self.verbose { print("meal created:", meal) }
				guard !SyncEngine.shared.hasPendingOperation(serverID: meal.id) else {
					if Self.verbose { print("Skipping meal create for pending entity:", meal.id) }
					return
				}
				self.mealsModel.addMealPlan(meal)
			}

		case "meal_plan_updated":
			decode(payload, as: MealPlan.self) { meal in
				if Self.verbose { print("meal updated:", meal) }
				guard !SyncEngine.shared.hasPendingOperation(serverID: meal.id) else {
					if Self.verbose { print("Skipping meal update for pending entity:", meal.id) }
					return
				}
				self.mealsModel.updateMealPlan(meal)
			}

		case "meal_plan_deleted":
			if let dict = payload as? [String: Any], let id = dict["id"] as? String {
				guard !SyncEngine.shared.hasPendingOperation(serverID: id) else {
					if Self.verbose { print("Skipping meal delete for pending entity:", id) }
					return
				}
				self.mealsModel.removeMealPlan(withId: id)
			}

		// MARK: Receipt Events
		case "receipt_created":
			decode(payload, as: Receipt.self) { receipt in
				if Self.verbose { print("receipt created:", receipt) }
				guard !SyncEngine.shared.hasPendingOperation(serverID: receipt.id) else {
					if Self.verbose {
						print("Skipping receipt create for pending entity:", receipt.id)
					}
					return
				}
				self.receiptsModel.addReceipt(receipt)
			}

		case "receipt_updated":
			decode(payload, as: Receipt.self) { receipt in
				if Self.verbose { print("receipt updated:", receipt) }
				guard !SyncEngine.shared.hasPendingOperation(serverID: receipt.id) else {
					if Self.verbose {
						print("Skipping receipt update for pending entity:", receipt.id)
					}
					return
				}
				self.receiptsModel.updateReceipt(receipt)
			}

		case "receipt_deleted":
			if let dict = payload as? [String: Any], let id = dict["id"] as? String {
				guard !SyncEngine.shared.hasPendingOperation(serverID: id) else {
					if Self.verbose { print("Skipping receipt delete for pending entity:", id) }
					return
				}
				self.receiptsModel.deleteReceipt(withId: id)
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

	func emitEcho(_ object: [String: Any]) {
		send(event: "echo", data: object)
	}
}
