//
//  ShoppingModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/17/25.
//

import Foundation

@MainActor
@Observable
class ShoppingModel {
	static let shared = ShoppingModel(groceriesModel: .shared)

	// Reference to shared GroceriesModel
	private let groceriesModel: GroceriesModel

	var errorMessage: String? = nil

	init(groceriesModel: GroceriesModel) {
		self.groceriesModel = groceriesModel
	}

	var isLoading: Bool {
		groceriesModel.isLoading
	}

	// MARK: Computed Properties
	var groceryItems: [GroceryItem] {
		groceriesModel.groceryItems
	}

	var shoppingItems: [GroceryItem] {
		groceryItems.filter { $0.isNeeded }
	}

	var uncheckedItems: [GroceryItem] {
		shoppingItems.filter { !$0.isShoppingChecked }
			.sorted { $0.category < $1.category }
	}

	var checkedItems: [GroceryItem] {
		shoppingItems.filter { $0.isShoppingChecked }
			.sorted { $0.category < $1.category }
	}

	// Delegate methods to GroceriesModel
	func fetchGroceries() async {
		await groceriesModel.fetchGroceries()
	}

	func updateGroceryItem(item: GroceryItem, field: GroceriesModel.GroceryItemField) {
		groceriesModel.updateGroceryItem(item: item, field: field)
	}

	// MARK: CRUD

	func createReceipt(price: Double, purchasedBy: String, notes: String) {
		errorMessage = nil
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let dateString = formatter.string(from: Date())

		SyncEngine.shared.enqueueReceiptCreate(
			date: dateString,
			totalAmount: price,
			purchasedBy: purchasedBy,
			notes: notes,
			checkedItems: checkedItems
		)

		SyncEngine.shared.reloadModels()
	}
}
