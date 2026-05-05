//
//  GroceriesModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import Foundation
import SwiftData

@MainActor
@Observable
class GroceriesModel {
	enum GroceryItemField {
		case isNeeded(Bool)
		case isShoppingChecked(Bool)
	}

	private let service: any GroceriesServicing
	private let syncEngine: SyncEngine

	var groceryItems: [GroceryItem] = []
	var isLoading = false
	var errorMessage: String? = nil
	var newItemName: String = ""
	var searchCategory: String = "Other"
	var selectedCategory: String = "Essentials"
	var expandedCategories: Set<String> = []
	var isSearching: Bool {
		!newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	let categories = ["Essentials", "Protein", "Veggies", "Carbs", "Household", "Other"]

	init(
		service: any GroceriesServicing = GroceriesService(),
		syncEngine: SyncEngine = .shared
	) {
		self.service = service
		self.syncEngine = syncEngine
	}

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
		guard !trimmedName.isEmpty else { return }

		if let existingItem = groceryItems.first(where: {
			$0.name.lowercased() == trimmedName.lowercased()
		}) {
			guard !existingItem.isNeeded else { return }
			updateGroceryItem(item: existingItem, field: GroceryItemField.isNeeded(true))
			return
		}

		createGroceryItem(name: trimmedName, category: searchCategory)
		expandedCategories.insert(searchCategory)
	}

	func selectExistingItem(_ item: GroceryItem) {
		updateGroceryItem(item: item, field: GroceryItemField.isNeeded(!item.isNeeded))
	}

	// MARK: UI Update Methods, used for WebSocket updates

	func addItem(_ item: GroceryItem) {
		if let index = groceryItems.firstIndex(where: { $0.id == item.id }) {
			groceryItems[index] = item
		} else {
			groceryItems.append(item)
		}
		if item.name.caseInsensitiveCompare(
			newItemName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
		{
			newItemName = ""
		}
	}

	func updateItem(_ updatedItem: GroceryItem) {
		if let index = groceryItems.firstIndex(where: { $0.id == updatedItem.id }) {
			groceryItems[index] = updatedItem
		}
		if updatedItem.name.caseInsensitiveCompare(
			newItemName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
		{
			newItemName = ""
		}
	}

	func removeItem(withId id: String) {
		groceryItems.removeAll { $0.id == id }
	}

	func replaceAll(with items: [GroceryItem]) {
		groceryItems = items
	}

	// MARK: CRUD Operations

	func fetchGroceries() {
		isLoading = true
		errorMessage = nil

		if !ConnectivityMonitor.shared.isOnline {
			groceryItems = syncEngine.loadAllGroceryItems()
			isLoading = false
			return
		}

		Task {
			do {
				let groceries = try await service.fetchGroceries()
				let merged = await MainActor.run {
					syncEngine.mergeGroceries(groceries)
				}

				await MainActor.run {
					self.groceryItems = merged
					self.isLoading = false
				}
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
					self.groceryItems = self.syncEngine.loadAllGroceryItems()
					self.isLoading = false
				}
			}
		}
	}

	func createGroceryItem(name: String, category: String) {
		errorMessage = nil

		if !ConnectivityMonitor.shared.isOnline {
			let created = syncEngine.enqueueGroceryCreate(name: name, category: category)
			groceryItems.append(created)

			if created.name.caseInsensitiveCompare(
				newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
			) == .orderedSame {
				newItemName = ""
			}
			return
		}

		let trimmedInput = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
		Task {
			do {
				_ = try await service.createGroceryItem(name: name, category: category)
				await MainActor.run {
					if !trimmedInput.isEmpty {
						self.newItemName = ""
					}
				}
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
				}
			}
		}
	}

	// PATCH method to update either isNeeded or isShoppingChecked
	func updateGroceryItem(item: GroceryItem, field: GroceryItemField) {
		errorMessage = nil

		let updatedValues: (isNeeded: Bool, isShoppingChecked: Bool)
		switch field {
		case .isNeeded(let isNeeded):
			updatedValues = (isNeeded, isNeeded ? false : item.isShoppingChecked)
		case .isShoppingChecked(let isShoppingChecked):
			updatedValues = (item.isNeeded, isShoppingChecked)
		}

		if !ConnectivityMonitor.shared.isOnline {
			guard
				let updated = syncEngine.enqueueGroceryUpdate(
					itemID: item.id,
					isNeeded: updatedValues.isNeeded,
					isShoppingChecked: updatedValues.isShoppingChecked
				)
			else {
				errorMessage = "Unable to update grocery item."
				return
			}

			updateItem(updated)
			return
		}

		Task {
			do {
				try await service.updateGroceryItem(
					id: item.id,
					isNeeded: updatedValues.isNeeded,
					isShoppingChecked: updatedValues.isShoppingChecked
				)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
				}
			}
		}
	}

	func deleteGroceryItem(item: GroceryItem) {
		errorMessage = nil

		if !ConnectivityMonitor.shared.isOnline {
			syncEngine.enqueueGroceryDelete(itemID: item.id)
			removeItem(withId: item.id)
			return
		}

		Task {
			do {
				try await service.deleteGroceryItem(id: item.id)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
				}
			}
		}
	}
}
