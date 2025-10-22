//
//  lebensmittelApp.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

@main
struct lebensmittelApp: App {
    @StateObject private var groceriesModel = GroceriesModel()
    @StateObject private var mealsModel = MealsModel()
    @StateObject private var receiptsModel = ReceiptsModel()
    @StateObject private var shoppingModel = ShoppingModel()
    
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
                }
        }
    }
}
