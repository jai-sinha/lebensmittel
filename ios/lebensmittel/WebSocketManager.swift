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
   
    // Models are required — they will be set when `start(...)` is called.
    // Use implicitly unwrapped types so they behave as non-optional after start is called.
    public private(set) var groceriesModel: GroceriesModel!
    public private(set) var shoppingModel: ShoppingModel!
    public private(set) var mealsModel: MealsModel!
    public private(set) var receiptsModel: ReceiptsModel!

    func start(
        with groceriesModel: GroceriesModel,
        mealsModel: MealsModel,
        receiptsModel: ReceiptsModel,
        shoppingModel: ShoppingModel
    ) {
        // store required models
        self.groceriesModel = groceriesModel
        self.mealsModel = mealsModel
        self.receiptsModel = receiptsModel
        self.shoppingModel = shoppingModel
         // Prevent double-starting
         if socket != nil { return }
         manager = SocketManager(socketURL: URL(string: "http://35.237.202.74")!,
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
        
        // MARK: Grocery Item Events

        socket.on("grocery_item_created") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: GroceryItem.self) { item in
                if Self.verbose { print("grocery created:", item) }
                self.groceriesModel.addItem(item)
            }
        }

        socket.on("grocery_item_updated") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: GroceryItem.self) { item in
                if Self.verbose { print("grocery updated:", item) }
                self.groceriesModel.updateItem(item)
            }
        }

        // Small helper to decode the server delete payload { "id": "..." }
        struct DeletedPayload: Decodable {
            let id: String
        }

        socket.on("grocery_item_deleted") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: DeletedPayload.self) { dp in
                self.groceriesModel.removeItem(withId: dp.id)
            }
        }
        
        // MARK: Meal Plan Events

        socket.on("meal_plan_created") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: MealPlan.self) { meal in
                if Self.verbose { print("meal created:", meal) }
                self.mealsModel.addMealPlan(meal)
            }
        }
        
        socket.on("meal_plan_deleted") { data, _ in guard let payload = data.first else { return }
            self.decode(payload, as: DeletedPayload.self) { dp in
                self.mealsModel.removeMealPlan(withId: dp.id)
            }
        }
        
        socket.on("meal_plan_updated") { data, _ in guard let payload = data.first else { return }
            self.decode(payload, as: MealPlan.self) { meal in
                // if Self.verbose { print("meal updated:", meal) }
                self.mealsModel.updateMealPlan(meal)

            }
        }
                    
        
        // MARK: Receipt Events

        socket.on("receipt_created") { data, _ in
            guard let payload = data.first else { return }
            // receipts items come as JSON string in server; server.to_dict should expose items array or string.
            self.decode(payload, as: Receipt.self) { receipt in
                if Self.verbose { print("receipt created:", receipt) }
                self.receiptsModel.addReceipt(receipt)
                self.shoppingModel.fetchGroceries()            }
        }
        
        socket.on("receipt_updated") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: Receipt.self) { receipt in
                if Self.verbose { print("receipt updated:", receipt) }
                self.receiptsModel.updateReceipt(receipt)
            }
        }
        
        socket.on("receipt_deleted") { data, _ in
            guard let payload = data.first else { return }
            self.decode(payload, as: DeletedPayload.self) { dp in
                self.receiptsModel.deleteReceipt(withId: dp.id)
            }
        }
        
        // MARK: Connection Events

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
