//
//  lebensmittelApp.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

@main
struct lebensmittelApp: App {
	@State private var groceriesModel: GroceriesModel
	@State private var mealsModel: MealsModel
	@State private var receiptsModel: ReceiptsModel
	@State private var shoppingModel: ShoppingModel

	// Initialize shoppingModel with groceriesModel reference
	init() {
		let groceries = GroceriesModel()
		_groceriesModel = State(initialValue: groceries)
		_mealsModel = State(initialValue: MealsModel())
		_receiptsModel = State(initialValue: ReceiptsModel())
		_shoppingModel = State(initialValue: ShoppingModel(groceriesModel: groceries))
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(groceriesModel)
				.environment(mealsModel)
				.environment(receiptsModel)
				.environment(shoppingModel)
				.onAppear {
					SocketService.shared.start(
						with: groceriesModel,
						mealsModel: mealsModel,
						receiptsModel: receiptsModel,
						shoppingModel: shoppingModel
					)
					// Initial data fetch
					groceriesModel.fetchGroceries()
					mealsModel.fetchMealPlans()
					receiptsModel.fetchReceipts()
				}
				.onReceive(
					NotificationCenter.default.publisher(
						for: UIApplication.willEnterForegroundNotification)
				) { _ in
					// Refresh data when app comes to foreground
					groceriesModel.fetchGroceries()
					mealsModel.fetchMealPlans()
					receiptsModel.fetchReceipts()
				}
		}
	}
}
