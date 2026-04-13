//
//  ServiceProtocols.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//
//
import Foundation

protocol GroceriesServicing {
	func fetchGroceries() async throws -> [GroceryItem]
	func createGroceryItem(name: String, category: String) async throws
	func updateGroceryItem(id: String, field: GroceriesModel.GroceryItemField) async throws
	func deleteGroceryItem(id: String) async throws
}

protocol MealsServicing {
	func fetchMealPlans() async throws -> [MealPlan]
	func createMealPlan(date: String, mealDescription: String) async throws
	func updateMealPlan(id: String, mealDescription: String) async throws
	func deleteMealPlan(id: String) async throws
}

protocol ReceiptsServicing {
	func fetchReceipts() async throws -> [Receipt]
	func updateReceipt(
		id: String,
		price: Double,
		purchasedBy: String,
		notes: String
	) async throws
	func deleteReceipt(id: String) async throws
}

protocol ShoppingServicing {
	func createReceipt(
		date: String,
		price: Double,
		purchasedBy: String,
		notes: String
	) async throws
}
