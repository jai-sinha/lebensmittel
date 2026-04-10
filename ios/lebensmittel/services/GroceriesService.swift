//
//  GroceriesService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//

import Foundation

struct GroceriesService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchGroceries() async throws -> [GroceryItem] {
        let response: GroceryItemsResponse = try await client.send(path: "/grocery-items")
        return response.groceryItems
    }

    func createGroceryItem(name: String, category: String) async throws {
        let item = NewGroceryItem(name: name, category: category)
        try await client.sendWithoutResponse(
            path: "/grocery-items",
            method: .POST,
            body: item
        )
    }

    func updateGroceryItem(id: String, field: GroceriesModel.GroceryItemField) async throws {
        var payload: [String: Bool] = [:]

        switch field {
        case .isNeeded(let value):
            payload["isNeeded"] = value
            payload["isShoppingChecked"] = false
        case .isShoppingChecked(let value):
            payload["isShoppingChecked"] = value
        }

        try await client.sendWithoutResponse(
            path: "/grocery-items/\(id)",
            method: .PATCH,
            body: payload
        )
    }

    func deleteGroceryItem(id: String) async throws {
        try await client.sendWithoutResponse(
            path: "/grocery-items/\(id)",
            method: .DELETE
        )
    }
}
