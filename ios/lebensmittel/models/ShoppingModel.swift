//
//  ShoppingModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/17/25.
//

import Foundation

@Observable
class ShoppingModel {
	// Reference to shared GroceriesModel
	private var groceriesModel: GroceriesModel

	var errorMessage: String? = nil

	init(groceriesModel: GroceriesModel) {
		self.groceriesModel = groceriesModel
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
		groceriesModel.isLoading = true
		errorMessage = nil
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		let dateString = formatter.string(from: Date())
		let payload = NewReceipt(
			date: dateString,
			totalAmount: price,
			purchasedBy: purchasedBy,
			notes: notes
		)
		let client = APIClient.shared

		Task {
			do {
				try await client.sendWithoutResponse(path: "/receipts", method: .POST, body: payload)
				// WebSocket should handle the update, fetching rn to be safe
				self.fetchGroceries()
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
					self.groceriesModel.isLoading = false
				}
			}
		}
	}
}
