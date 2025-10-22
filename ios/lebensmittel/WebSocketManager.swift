//
//  WebSocketManager.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/22/25.
//

import Foundation
import SocketIO

// Simple singleton socket manager
final class SocketService {
    static let shared = SocketService()

    // Toggle this to true if you need verbose socket logs for debugging
    static var verbose = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    public var groceriesModel: GroceriesModel?

    // Call this from the App after creating the GroceriesModel so the service can connect and receive events that update the model immediately.
    func start(with model: GroceriesModel) {
        // Prevent double-starting
        if socket != nil { return }
        self.groceriesModel = model
        if Self.verbose { print("SocketService.start: using GroceriesModel id:\(ObjectIdentifier(model))") }
        manager = SocketManager(socketURL: URL(string: "http://192.168.2.113:8000")!,
                                config: [.log(false), .compress])
        socket = manager!.defaultSocket
        addHandlers()
        socket!.connect()
    }

    private func addHandlers() {
        guard let socket = socket else { return }

        socket.on(clientEvent: .connect) { _, _ in
            if Self.verbose { print("Socket connected") }
        }

        socket.on("grocery_item_created") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: GroceryItem.self) { item in
                if Self.verbose { print("grocery created:", item) }
                self.groceriesModel?.addItem(item)
            }
        }

        socket.on("grocery_item_updated") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: GroceryItem.self) { item in
                if Self.verbose { print("grocery updated:", item) }
                self.groceriesModel?.updateItem(item)
            }
        }

        // Small helper to decode the server delete payload { "id": "..." }
        struct DeletedPayload: Decodable {
            let id: String
        }

        socket.on("grocery_item_deleted") { data, _ in
            if Self.verbose { print("grocery deleted raw payload:", data) }
            guard let payload = data.first else { return }
            self.decode(payload, as: DeletedPayload.self) { dp in
                if let id = UUID(uuidString: dp.id) {
                    self.groceriesModel?.removeItem(withId: id)
                } else if Self.verbose {
                    print("grocery_item_deleted: invalid uuid string:\(dp.id)")
                }
            }
        }

        socket.on("meal_plan_created") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: MealPlan.self) { meal in
                if Self.verbose { print("meal created:", meal) }
            }
        }

        socket.on("receipt_created") { data, _ in
            guard let payload = data.first else { return }
            // receipts items come as JSON string in server; server.to_dict should expose items array or string.
            self.decode(payload, as: Receipt.self) { receipt in
                if Self.verbose { print("receipt created:", receipt) }
            }
        }

        socket.on(clientEvent: .disconnect) { _, _ in
            if Self.verbose { print("Socket disconnected") }
        }

        socket.on("connected") { data, _ in
            if Self.verbose { print("server connected msg:", data) }
        }

        // test echo if needed
        socket.on("message") { data, _ in
            if Self.verbose { print("message:", data) }
        }
    }

    private func decode<T: Decodable>(_ payload: Any, as type: T.Type, _ completion: @escaping (T) -> Void) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            let obj = try JSONDecoder().decode(T.self, from: jsonData)
            DispatchQueue.main.async { completion(obj) }
        } catch {
            print("socket decode error:", error, "payload:", payload)
        }
    }

    func emitEcho(_ object: [String: Any]) {
        socket?.emit("echo", object)
    }
}
