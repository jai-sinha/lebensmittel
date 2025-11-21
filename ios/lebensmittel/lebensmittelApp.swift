//
//  lebensmittelApp.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

@main
struct lebensmittelApp: App {
    @StateObject private var groceriesModel: GroceriesModel
    @StateObject private var mealsModel: MealsModel
    @StateObject private var receiptsModel: ReceiptsModel
    @StateObject private var shoppingModel: ShoppingModel
    
    // Initialize shoppingModel with groceriesModel reference
    init() {
        let groceries = GroceriesModel()
        _groceriesModel = StateObject(wrappedValue: groceries)
        _mealsModel = StateObject(wrappedValue: MealsModel())
        _receiptsModel = StateObject(wrappedValue: ReceiptsModel())
        _shoppingModel = StateObject(wrappedValue: ShoppingModel(groceriesModel: groceries))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(groceriesModel)
                .environmentObject(mealsModel)
                .environmentObject(receiptsModel)
                .environmentObject(shoppingModel)
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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Refresh data when app comes to foreground
                    groceriesModel.fetchGroceries()
                    mealsModel.fetchMealPlans()
                    receiptsModel.fetchReceipts()
                }
        }
    }
}
