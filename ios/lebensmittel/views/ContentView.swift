//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView() {
            GroceriesView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Groceries")
                }
                .tag(0)
            
            MealsView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Meals")
                }
                .tag(1)
            
            ShoppingView()
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
