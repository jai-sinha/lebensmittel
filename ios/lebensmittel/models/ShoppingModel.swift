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
	private let receiptsService: any ReceiptsServicing
	private let syncEngine: SyncEngine

	var errorMessage: String? = nil

	init(
		groceriesModel: GroceriesModel,
		receiptsService: any ReceiptsServicing = ReceiptsService(),
		syncEngine: SyncEngine = .shared
	) {
		self.groceriesModel = groceriesModel
		self.receiptsService = receiptsService
		self.syncEngine = syncEngine
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

		if !ConnectivityMonitor.shared.isOnline {
			let optimisticReceipt = syncEngine.enqueueReceiptCreate(
				date: dateString,
				totalAmount: price,
				purchasedBy: purchasedBy,
				notes: notes,
				checkedItems: checkedItems
			)

			groceriesModel.groceryItems = syncEngine.loadAllGroceryItems()
			if let receiptsModel = SocketService.shared.receiptsModel {
				receiptsModel.receipts = syncEngine.loadAllReceipts()
			} else {
				_ = optimisticReceipt
			}
			return
		}

		let itemNames = checkedItems.map { $0.name }
		Task {
			do {
				_ = try await receiptsService.createReceipt(
					NewReceipt(
						date: dateString,
						totalAmount: price,
						purchasedBy: purchasedBy,
						items: itemNames,
						notes: notes
					)
				)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
				}
			}
		}
	}
}
