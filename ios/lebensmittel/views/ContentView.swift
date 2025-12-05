//
//  ContentView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ContentView: View {
	var body: some View {
		TabView {
			GroceriesView()
			Tab {
				Image(systemName: "list.bullet")
				Text("Groceries")
			}
			.tag(0)

			MealsView()
			Tab {
				Image(systemName: "calendar")
				Text("Meals")
			}
			.tag(1)

			ShoppingView()
			Tab {
				Image(systemName: "cart")
				Text("Shopping")
			}
			.tag(2)
			ReceiptsView()
			Tab {
				Image(systemName: "receipt")
				Text("Receipts")
			}
			.tag(3)
		}
	}
}

#Preview {
	ContentView()
}
