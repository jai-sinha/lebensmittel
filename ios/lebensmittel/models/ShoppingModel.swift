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

	// MARK: CRUD Operations

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
		guard let url = URL(string: "http://35.237.202.74:8000/api/receipts"),
			let body = try? JSONEncoder().encode(payload)
		else {
			errorMessage = "Invalid URL or payload"
			groceriesModel.isLoading = false
			return
		}
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = body
		Task {
			do {
				let (_, response) = try await URLSession.shared.data(for: request)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					await MainActor.run {
						self.errorMessage = "Failed to create receipt"
						self.groceriesModel.isLoading = false
					}
				} else {
					await MainActor.run {
						// WebSocket will handle the update, but fetch to be safe
						self.fetchGroceries()
						self.groceriesModel.isLoading = false
					}
				}
			} catch {
				await MainActor.run {
					self.errorMessage = error.localizedDescription
					self.groceriesModel.isLoading = false
				}
			}
		}
	}
}
