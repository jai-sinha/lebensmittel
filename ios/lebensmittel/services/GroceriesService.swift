//
//  GroceriesService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//

import Foundation

struct GroceriesService {
	static let shared = GroceriesService()

	private var client: APIClient { .shared }

	func createGroceryItem(_ item: NewGroceryItem) async throws -> GroceryItem {
		return try await client.send(
			path: "/grocery-items",
			method: .POST,
			body: item
		)
	}

	func updateGroceryItem(
		id: UUID,
		isNeeded: Bool,
		isShoppingChecked: Bool,
		category: String?,
		name: String?
	) async throws {
		try await client.sendWithoutResponse(
			path: "/grocery-items/\(id.uuidString.lowercased())",
			method: .PATCH,
			body: GroceryItemUpdatePayload(
				isNeeded: isNeeded,
				isShoppingChecked: isShoppingChecked,
				category: category,
				name: name,
			)
		)
	}

	func deleteGroceryItem(id: UUID) async throws {
		try await client.sendWithoutResponse(
			path: "/grocery-items/\(id.uuidString.lowercased())",
			method: .DELETE
		)
	}
}

private struct GroceryItemUpdatePayload: Encodable {
	let isNeeded: Bool
	let isShoppingChecked: Bool
	let category: String?
	let name: String?
}
