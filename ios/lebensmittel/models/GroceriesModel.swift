//
//  GroceriesModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
class GroceriesModel {
	private let groupModel: GroupModel

	var categories: [String] {
		groupModel.activeGroup?.categories ?? []
	}

	enum GroceryItemField {
		case isNeeded(Bool)
		case isShoppingChecked(Bool)
		case category(String)
		case name(String)
	}

	private let syncEngine: SyncEngine

	var groceryItems: [GroceryItem] = []
	var isLoading = false
	var errorMessage: String? = nil
	var newItemName: String = ""

	private var storedSelectedCategory: String = ""
	var selectedCategory: String {
		get {
			categories.contains(storedSelectedCategory)
				? storedSelectedCategory
				: categories.first ?? ""
		}
		set { storedSelectedCategory = newValue }
	}

	var expandedCategories: Set<String> = []
	var isSearching: Bool {
		!newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	init(
		groupModel: GroupModel = .shared,
		syncEngine: SyncEngine = .shared
	) {
		self.groupModel = groupModel
		self.syncEngine = syncEngine
	}

	// MARK: Computed properties and helpers

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

		createGroceryItem(name: trimmedName, category: selectedCategory)
		expandedCategories.insert(selectedCategory)
	}

	func selectExistingItem(_ item: GroceryItem) {
		updateGroceryItem(item: item, field: GroceryItemField.isNeeded(!item.isNeeded))
	}

	// MARK: UI update methods

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

	func removeItem(withId id: UUID) {
		groceryItems.removeAll { $0.id == id }
	}

	func replaceAll(with items: [GroceryItem]) {
		groceryItems = items
	}

	// MARK: CRUD

	func fetchGroceries() async {
		errorMessage = nil

		guard ConnectivityMonitor.shared.isOnline else { return }

		isLoading = true
		defer { isLoading = false }

		do {
			try await syncEngine.reconcile(forceSnapshot: true)
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func createGroceryItem(name: String, category: String) {
		errorMessage = nil
		let created = syncEngine.enqueueGroceryCreate(name: name, category: category)
		groceryItems.append(created)
		if created.name.caseInsensitiveCompare(
			newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
		) == .orderedSame {
			newItemName = ""
		}
	}

	func updateGroceryItem(item: GroceryItem, field: GroceryItemField) {
		errorMessage = nil

		var isNeeded = item.isNeeded
		var isShoppingChecked = item.isShoppingChecked
		var category: String? = nil
		var name: String? = nil

		switch field {
		case .isNeeded(let value):
			isNeeded = value
			if value { isShoppingChecked = false }
		case .isShoppingChecked(let value):
			isShoppingChecked = value
		case .category(let value):
			category = value
		case .name(let value):
			name = value
		}

		guard
			let updated = syncEngine.enqueueGroceryUpdate(
				itemID: item.id,
				isNeeded: isNeeded,
				isShoppingChecked: isShoppingChecked,
				category: category,
				name: name,
			)
		else {
			errorMessage = "Unable to update grocery item."
			return
		}

		if let index = groceryItems.firstIndex(where: { $0.id == updated.id }) {
			groceryItems[index] = updated
		}
	}

	func deleteGroceryItem(item: GroceryItem) {
		errorMessage = nil
		syncEngine.enqueueGroceryDelete(itemID: item.id)
		removeItem(withId: item.id)
	}
}
