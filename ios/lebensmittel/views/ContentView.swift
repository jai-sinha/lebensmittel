//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
	@Environment(SessionManager.self) var sessionManager

	var body: some View {
		TabView {
			Tab("Groceries", systemImage: "list.bullet") {
				GroceriesView()
			}

			Tab("Meals", systemImage: "calendar") {
				MealsView()
			}

			Tab("Shopping", systemImage: "cart") {
				ShoppingView()
			}

			Tab("Receipts", systemImage: "receipt") {
				ReceiptsView()
			}
		}
	}
}
