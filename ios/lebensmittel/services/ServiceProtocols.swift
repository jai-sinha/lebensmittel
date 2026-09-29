//
//  ServiceProtocols.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//
//
import Foundation

protocol GroceriesServicing: Sendable {
	func createGroceryItem(_ item: NewGroceryItem) async throws -> GroceryItem
	func updateGroceryItem(
		id: String,
		isNeeded: Bool,
		isShoppingChecked: Bool
	) async throws
	func deleteGroceryItem(id: String) async throws
}

protocol MealsServicing: Sendable {
	func createMealPlan(_ plan: NewMealPlan) async throws -> MealPlan
	func updateMealPlan(id: String, mealDescription: String) async throws
	func deleteMealPlan(id: String) async throws
}

protocol ReceiptsServicing: Sendable {
	func createReceipt(_ receipt: NewReceipt) async throws -> Receipt
	func updateReceipt(
		id: String,
		price: Double,
		purchasedBy: String,
		notes: String
	) async throws
	func deleteReceipt(id: String) async throws
}

protocol ShoppingServicing: Sendable {
	func createReceipt(
		date: String,
		price: Double,
		purchasedBy: String,
		items: [String],
		notes: String
	) async throws
}

protocol GroupServicing: Sendable {
	func fetchGroup(id: String) async throws -> AuthGroup
	func createGroup(name: String) async throws -> AuthGroup
	func renameGroup(id: String, name: String) async throws -> AuthGroup
	func updateGroupCategories(id: String, categories: [String]) async throws -> AuthGroup
	func updateGroupMembers(id: String, members: [String]) async throws -> AuthGroup
	func fetchLegacyGroups(for userID: String) async throws -> [String]
}
