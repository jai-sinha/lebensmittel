//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appData = AppData()
    @StateObject private var mealsModel: MealsModel
    
    init() {
        let appData = AppData()
        _appData = StateObject(wrappedValue: appData)
        _mealsModel = StateObject(wrappedValue: MealsModel())
    }
    
    var body: some View {
        TabView() {
            GroceriesView(appData: appData)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Groceries")
                }
                .tag(0)
            
            MealsView(mealsModel: mealsModel)
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Meals")
                }
                .tag(1)
            
            ShoppingView(appData: appData)
                .tabItem {
                    Image(systemName: "cart")
                    Text("Shopping")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
