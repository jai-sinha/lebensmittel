//
//  MealsService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/10/26.
//

import Foundation

struct MealsService: MealsServicing {
	private let client: APIClient

	init(client: APIClient = .shared) {
		self.client = client
	}

	func fetchMealPlans() async throws -> [MealPlan] {
		let response: MealPlansResponse = try await client.send(path: "/meal-plans")
		return response.mealPlans
	}

	func createMealPlan(date: String, mealDescription: String) async throws -> MealPlan {
		let payload = NewMealPlan(date: date, mealDescription: mealDescription)
		return try await client.send(
			path: "/meal-plans",
			method: .POST,
			body: payload
		)
	}

	func updateMealPlan(id: String, mealDescription: String) async throws {
		try await client.sendWithoutResponse(
			path: "/meal-plans/\(id)",
			method: .PATCH,
			body: ["mealDescription": mealDescription]
		)
	}

	func deleteMealPlan(id: String) async throws {
		try await client.sendWithoutResponse(
			path: "/meal-plans/\(id)",
			method: .DELETE
		)
	}
}
