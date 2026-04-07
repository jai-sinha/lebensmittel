//
//  MealsModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import Foundation

@Observable
class MealsModel {
	var mealPlans: [String: MealPlan] = [:]  // Keyed by date string
	var errorMessage: String? = nil

	init() {}

	func getMealPlan(for dateString: String) -> String {
		return mealPlans[dateString]?.mealDescription ?? ""
	}

	func mealPlanId(for dateString: String) -> String? {
		return mealPlans[dateString]?.id
	}

	// MARK: UI Update Methods, used for WebSocket updates

	func addMealPlan(_ plan: MealPlan) {
		mealPlans[plan.date] = plan
	}

	func updateMealPlan(_ plan: MealPlan) {
		if var existingPlan = mealPlans[plan.date] {
			existingPlan.mealDescription = plan.mealDescription
			mealPlans[plan.date] = existingPlan
		}
	}

	func removeMealPlan(withId id: String) {
		if let key = mealPlans.first(where: { $0.value.id == id })?.key {
			mealPlans.removeValue(forKey: key)
		}
	}

	// MARK: CRUD Operations

	func fetchMealPlans() {
		let client = APIClient()

		Task {
			do {
				let response: MealPlansResponse = try await client.send(path: "/meal-plans")
				await MainActor.run {
					self.mealPlans.removeAll()
					for mealPlan in response.mealPlans {
						self.mealPlans[mealPlan.date] = mealPlan
					}
				}
			} catch {
				print("Decoding error: \(error)")
			}
		}
	}

	func createMealPlan(for dateString: String, meal: String) {
		let newMealPlan = NewMealPlan(date: dateString, mealDescription: meal)
		let client = APIClient()

		Task {
			do {
				try await client.sendVoid(path: "/meal-plans", method: .POST, body: newMealPlan)
			} catch {
				print("Create meal plan error: \(error)")
				await MainActor.run {
					self.fetchMealPlans()
				}
			}
		}
	}

	func updateMealPlan(for dateString: String, meal: String) {
		guard let existingPlan = mealPlans[dateString] else { return }
		if existingPlan.mealDescription == meal { return } // No change, skip update

		let updatePayload = ["mealDescription": meal]
		let client = APIClient()

		Task {
			do {
				try await client.sendVoid(path: "/meal-plans/\(existingPlan.id)", method: .PATCH, body: updatePayload)
			} catch {
				print("Update meal plan error: \(error)")
				await MainActor.run {
					self.fetchMealPlans()
				}
			}
		}
	}


	func deleteMealPlan(mealId: String) {
		let client = APIClient()

		Task {
			do {
				try await client.sendVoid(path: "/meal-plans/\(mealId)", method: .DELETE)
			} catch {
				print("Delete meal plan error: \(error)")
				await MainActor.run {
					self.fetchMealPlans()
				}
			}
		}
	}

	/// Returns a "yyyy-MM-dd" string representing the user's local calendar date for the given Date.
	/// Intentionally uses the device's current timezone — NOT UTC — so that "Oct 20" in the UI
	/// always maps to the string "2025-10-20" regardless of what timezone the user is in.
	static func calendarDateString(for date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.timeZone = TimeZone.current
		return formatter.string(from: date)
	}

	var dateFormatter: DateFormatter {
		let formatter = DateFormatter()
		formatter.dateFormat = "MMM d"
		formatter.timeZone = TimeZone.current
		return formatter
	}

	var dayFormatter: DateFormatter {
		let formatter = DateFormatter()
		formatter.dateFormat = "EEE"
		formatter.timeZone = TimeZone.current
		return formatter
	}
}
