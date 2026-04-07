//
//  GroceriesModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import Foundation

@Observable
class GroceriesModel {
	var groceryItems: [GroceryItem] = []
	var isLoading = false
	var errorMessage: String? = nil
	var newItemName: String = ""
	var searchCategory: String = "Other"
	var selectedCategory: String = "Essentials"
	var expandedCategories: Set<String> = []
	var isSearching: Bool = false

	let categories = ["Essentials", "Protein", "Veggies", "Carbs", "Household", "Other"]

	// MARK: Computed Properties and Helpers

	var searchResults: [GroceryItem] {
		guard !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return []
		}
		let searchTerm = newItemName.lowercased()
		return groceryItems.filter { item in
			item.name.lowercased().contains(searchTerm)
		}.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	var exactMatch: GroceryItem? {
		let trimmedName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
		return groceryItems.first {
			$0.name.lowercased() == trimmedName.lowercased()
		}
	}

	var itemsByCategory: [String: [GroceryItem]] {
		Dictionary(grouping: groceryItems) { $0.category }
	}

	var sortedCategories: [String] {
		let categoriesWithItems = Array(itemsByCategory.keys).sorted()
		let emptyCategories = Array(categories.filter { !itemsByCategory.keys.contains($0) })
		return categoriesWithItems + emptyCategories
	}

	var essentialsItems: [GroceryItem] {
		itemsByCategory["Essentials"] ?? []
	}

	var otherCategories: [String] {
		categories.filter { $0 != "Essentials" }
	}

	func addItem() {
		let trimmedName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
		if !trimmedName.isEmpty {
			if let existingItem = groceryItems.first(where: {
				$0.name.lowercased() == trimmedName.lowercased()
			}) {
				if !existingItem.isNeeded {
					updateGroceryItem(item: existingItem, field: GroceryItemField.isNeeded(true))
				}
			} else {
				createGroceryItem(name: trimmedName, category: searchCategory)
				expandedCategories.insert(searchCategory)
			}
			newItemName = ""
			isSearching = false
		}
	}

	func selectExistingItem(_ item: GroceryItem) {
		updateGroceryItem(item: item, field: GroceryItemField.isNeeded(!item.isNeeded))
		newItemName = ""
		isSearching = false
	}

	// MARK: UI Update Methods, used for WebSocket updates

	func addItem(_ item: GroceryItem) {
		groceryItems.append(item)
	}

	func updateItem(_ updatedItem: GroceryItem) {
		if let index = groceryItems.firstIndex(where: { $0.id == updatedItem.id }) {
			groceryItems[index] = updatedItem
		}
	}

	func removeItem(withId id: String) {
		groceryItems.removeAll { $0.id == id }
	}

	// MARK: CRUD Operations

	func fetchGroceries() {
		isLoading = true
		errorMessage = nil
		let client = APIClient()

		Task {
			do {
				let response: GroceryItemsResponse = try await client.send(path: "/grocery-items")

				await MainActor.run {
					self.groceryItems = response.groceryItems
					self.isLoading = false
				}
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
					self.isLoading = false
				}
			}
		}
	}

	func createGroceryItem(name: String, category: String) {
		errorMessage = nil

		let newItem = NewGroceryItem(name: name, category: category)
		let client = APIClient()

		Task {
			do {
				try await client.sendWithoutResponse(
					path: "/grocery-items",
					method: .POST,
					body: newItem
				)
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
				}
			}
		}
	}

	enum GroceryItemField {
		case isNeeded(Bool)
		case isShoppingChecked(Bool)
	}

	// PATCH method to update either isNeeded or isShoppingChecked
	func updateGroceryItem(item: GroceryItem, field: GroceryItemField) {
		errorMessage = nil

		var updatePayload: [String: Bool] = [:]
		switch field {
		case .isNeeded(let value):
			updatePayload["isNeeded"] = value
			updatePayload["isShoppingChecked"] = false
		case .isShoppingChecked(let value):
			updatePayload["isShoppingChecked"] = value
		}

		let client = APIClient()

		Task {
			do {
				try await client.sendWithoutResponse(
					path: "/grocery-items/\(item.id)",
					method: .PATCH,
					body: updatePayload
				)
				// WebSocket will handle updating the UI via grocery_item_updated event
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
				}
			}
		}
	}

	func deleteGroceryItem(item: GroceryItem) {
		errorMessage = nil

		let client = APIClient()

		Task {
			do {
				try await client.sendWithoutResponse(
					path: "/grocery-items/\(item.id)",
					method: .DELETE
				)
				// WebSocket will handle updating the UI via grocery_item_deleted event
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
				}
			}
		}
	}
}
