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

	func createMealPlan(_ plan: NewMealPlan) async throws -> MealPlan {
		return try await client.send(
			path: "/meal-plans",
			method: .POST,
			body: plan
		)
	}

	func updateMealPlan(id: UUID, mealDescription: String) async throws {
		try await client.sendWithoutResponse(
			path: "/meal-plans/\(id.uuidString.lowercased())",
			method: .PATCH,
			body: ["mealDescription": mealDescription]
		)
	}

	func deleteMealPlan(id: UUID) async throws {
		try await client.sendWithoutResponse(
			path: "/meal-plans/\(id.uuidString.lowercased())",
			method: .DELETE
		)
	}
}
