//
//  Models.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import Foundation
import Combine

struct Receipt: Identifiable, Codable {
    var id: String
    var date: String
    var totalAmount: Double
    var purchasedBy: String
    var items: [String]
    var notes: String
}

struct NewReceipt: Codable {
    var date: String
    var totalAmount: Double
    var purchasedBy: String
    var notes: String
}

struct ReceiptsResponse: Codable {
    let count: Int
    let receipts: [Receipt]
}

struct GroceryItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var category: String
    var isNeeded: Bool = true // true = need to buy, false = have it
    var isShoppingChecked: Bool = false // checked off in shopping list
}

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
