//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appData = AppData()
    
    var body: some View {
        TabView {
            GroceriesView(appData: appData)
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Groceries")
                }
            
            MealsView(appData: appData)
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Meals")
                }
            
            ShoppingView(appData: appData)
                .tabItem {
                    Image(systemName: "cart")
                    Text("Shopping")
                }
        }
    }
}

#Preview {
    ContentView()
}