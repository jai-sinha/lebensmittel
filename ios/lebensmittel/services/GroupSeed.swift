//
//  GroupSeed.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/2/26.
//

import Foundation

enum GroupSeed {
	struct StarterGrocery {
		let name: String
		let category: String
	}

	static let starterGroceries: [StarterGrocery] = [
		StarterGrocery(name: "Eggs", category: "Essentials"),
		StarterGrocery(name: "Olive oil", category: "Other"),
		StarterGrocery(name: "Chicken breasts", category: "Protein"),
		StarterGrocery(name: "Red onion", category: "Veggies"),
		StarterGrocery(name: "Coffee beans", category: "Other"),
		StarterGrocery(name: "Tortillas", category: "Carbs"),
		StarterGrocery(name: "Jasmine rice", category: "Carbs"),
		StarterGrocery(name: "Beer", category: "Essentials"),
		StarterGrocery(name: "Whitefish", category: "Protein"),
		StarterGrocery(name: "Salmon", category: "Protein"),
		StarterGrocery(name: "Frozen pizza", category: "Essentials"),
		StarterGrocery(name: "Toilet paper", category: "Household"),
		StarterGrocery(name: "Cabbage", category: "Veggies"),
		StarterGrocery(name: "Dishwasher pods", category: "Household"),
		StarterGrocery(name: "Tofu", category: "Protein"),
		StarterGrocery(name: "Bananas", category: "Essentials"),
		StarterGrocery(name: "Leafy greens", category: "Veggies"),
		StarterGrocery(name: "Avocados", category: "Essentials"),
		StarterGrocery(name: "Turkey", category: "Essentials"),
		StarterGrocery(name: "Ground beef", category: "Protein"),
		StarterGrocery(name: "Spaghetti", category: "Essentials"),
		StarterGrocery(name: "Milk", category: "Essentials"),
		StarterGrocery(name: "Limes", category: "Essentials"),
		StarterGrocery(name: "Garlic", category: "Other"),
		StarterGrocery(name: "Sliced bread", category: "Essentials"),
		StarterGrocery(name: "Pickles", category: "Veggies"),
	]

	static let exampleReceiptItems = [ "Milk", "Juice", "Eggs", "Turkey", "Cilantro" ]
}
