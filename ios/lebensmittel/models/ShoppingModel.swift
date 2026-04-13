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
	// Reference to shared GroceriesModel
	private var groceriesModel: GroceriesModel
	private let service: any ShoppingServicing

	var errorMessage: String? = nil

	init(groceriesModel: GroceriesModel, service: any ShoppingServicing = ShoppingService()) {
		self.groceriesModel = groceriesModel
		self.service = service
	}

	// Delegate isLoading to groceriesModel
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
	func fetchGroceries() {
		groceriesModel.fetchGroceries()
	}

	func updateGroceryItem(item: GroceryItem, field: GroceriesModel.GroceryItemField) {
		groceriesModel.updateGroceryItem(item: item, field: field)
	}

	// MARK: CRUD Operation (just createReceipt)

	func createReceipt(price: Double, purchasedBy: String, notes: String) {
		errorMessage = nil
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let dateString = formatter.string(from: Date())

		Task {
			do {
				try await service.createReceipt(
					date: dateString,
					price: price,
					purchasedBy: purchasedBy,
					notes: notes
				)
			} catch {
				self.errorMessage = UserFacingError.message(for: error)
			}
		}
	}
}
