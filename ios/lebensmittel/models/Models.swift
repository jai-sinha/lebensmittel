//
//  Models.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import Foundation

// MARK: Receipts

struct Receipt: Identifiable, Codable {
	var id: String
	var date: String
	var totalAmount: Double
	var purchasedBy: String
	var items: [String]
	var notes: String?
}

struct NewReceipt: Codable {
	var date: String
	var totalAmount: Double
	var purchasedBy: String
	var notes: String?
}

struct ReceiptsResponse: Codable {
	let count: Int
	let receipts: [Receipt]
}

struct MonthlyReceiptsGroup: Identifiable {
	let id = UUID()
	let month: String
	let receipts: [Receipt]
	let userTotals: [String: Double]
}

// MARK: Grocery Items

struct GroceryItem: Identifiable, Codable {
	var id: String
	var name: String
	var category: String
	var isNeeded: Bool = true  // true = need to buy, false = have it
	var isShoppingChecked: Bool = false  // checked off in shopping list
}

struct GroceryItemsResponse: Codable {
	let count: Int
	let groceryItems: [GroceryItem]
}

struct NewGroceryItem: Codable {
	var name: String
	var category: String
	var isNeeded: Bool = true
	var isShoppingChecked: Bool = false
}

struct UpdateGroceryItem: Codable {
	var name: String
	var category: String
	var isNeeded: Bool
	var isShoppingChecked: Bool
}

// MARK: Meal Plans

struct MealPlan: Identifiable, Codable, Equatable {
	var id: String
	var date: String
	var mealDescription: String
}

struct NewMealPlan: Codable {
	var date: String
	var mealDescription: String
}

struct MealPlansResponse: Codable {
	let count: Int
	let mealPlans: [MealPlan]
}

// MARK: Groups

struct AuthGroup: Identifiable, Codable, Hashable, Sendable {
	let id: String
	let name: String

	enum CodingKeys: String, CodingKey {
		case id
		case name
	}

	nonisolated init(id: String, name: String) {
		self.id = id
		self.name = name
	}

	nonisolated init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.id = try container.decode(String.self, forKey: .id)
		self.name = try container.decode(String.self, forKey: .name)
	}

	nonisolated func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(id, forKey: .id)
		try container.encode(name, forKey: .name)
	}
}
