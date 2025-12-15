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
	var selectedCategory: String = "Other"
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
				createGroceryItem(name: trimmedName, category: selectedCategory)
				expandedCategories.insert(selectedCategory)
			}
			newItemName = ""
			isSearching = false
		}
	}

	func selectExistingItem(_ item: GroceryItem) {
		if !item.isNeeded {
			updateGroceryItem(item: item, field: GroceryItemField.isNeeded(true))
		}
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
		guard let url = URL(string: "https://ls.jsinha.com/api/grocery-items") else {
			errorMessage = "Invalid URL"
			isLoading = false
			return
		}
		Task {
			do {
				let (data, _) = try await URLSession.shared.data(from: url)
				let response = try JSONDecoder().decode(GroceryItemsResponse.self, from: data)
				groceryItems = response.groceryItems
				isLoading = false
			} catch {
				errorMessage = error.localizedDescription
				isLoading = false
			}
		}
	}

	func createGroceryItem(name: String, category: String) {
		isLoading = true
		errorMessage = nil
		guard let url = URL(string: "https://ls.jsinha.com/api/grocery-items") else {
			errorMessage = "Invalid URL"
			isLoading = false
			return
		}
		let newItem = NewGroceryItem(name: name, category: category)
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONEncoder().encode(newItem)
		Task {
			do {
				let (_, response) = try await URLSession.shared.data(for: request)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					await MainActor.run {
						self.errorMessage = "Server returned status \(http.statusCode)"
						self.isLoading = false
					}
				} else {
					await MainActor.run {
						self.isLoading = false
						// WebSocket will handle updating the UI via grocery_item_created event
					}
				}
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
					self.isLoading = false
				}
			}
		}
	}

	enum GroceryItemField {
		case isNeeded(Bool)
		case isShoppingChecked(Bool)
	}

	// PUT method to update either isNeeded or isShoppingChecked
	func updateGroceryItem(item: GroceryItem, field: GroceryItemField) {
		errorMessage = nil
		guard let url = URL(string: "https://ls.jsinha.com/api/grocery-items/\(item.id)") else {
			errorMessage = "Invalid URL"
			return
		}

		// Build updated item for the request
		var updatedItem = item
		switch field {
		case .isNeeded(let value):
			updatedItem.isNeeded = value
		case .isShoppingChecked(let value):
			updatedItem.isShoppingChecked = value
		}

		// Send full item in PUT request
		let updatePayload = UpdateGroceryItem(
			name: updatedItem.name,
			category: updatedItem.category,
			isNeeded: updatedItem.isNeeded,
			isShoppingChecked: updatedItem.isShoppingChecked
		)
		guard let jsonBody = try? JSONEncoder().encode(updatePayload) else {
			errorMessage = "Failed to encode update payload"
			return
		}
		var request = URLRequest(url: url)
		request.httpMethod = "PUT"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = jsonBody
		Task {
			do {
				let (_, response) = try await URLSession.shared.data(for: request)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					await MainActor.run {
						self.errorMessage = "Server returned status \(http.statusCode)"
					}
				}
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
		guard let url = URL(string: "https://ls.jsinha.com/api/grocery-items/\(item.id)") else {
			errorMessage = "Invalid URL"
			return
		}

		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"
		Task {
			do {
				let (_, response) = try await URLSession.shared.data(for: request)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					await MainActor.run {
						self.errorMessage = "Server returned status \(http.statusCode)"
					}
				}
				// WebSocket will handle updating the UI via grocery_item_deleted event
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
				}
			}
		}
	}
}
