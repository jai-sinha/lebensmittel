//
//  MealsModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import Foundation
import SwiftUI

@Observable
class MealsModel {
	var baseDate: Date
	var mealPlans: [String: MealPlan] = [:]  // Keyed by date string

	init(baseDate: Date = Calendar.current.startOfDay(for: Date())) {
		self.baseDate = baseDate
	}

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
		guard let url = URL(string: "https://ls.jsinha.com/api/meal-plans") else { return }

		let client = NetworkClient()

		Task {
			do {
				var request = URLRequest(url: url)
				request.httpMethod = "GET"
				let (data, _) = try await client.send(request)
				let response = try JSONDecoder().decode(MealPlansResponse.self, from: data)
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
		guard let url = URL(string: "https://ls.jsinha.com/api/meal-plans") else { return }
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		let newMealPlan = NewMealPlan(date: dateString, mealDescription: meal)
		request.httpBody = try? JSONEncoder().encode(newMealPlan)
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let client = NetworkClient()

		Task {
			do {
				let (_, response) = try await client.send(request)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					print("Server returned status \(http.statusCode)")
				}
				await MainActor.run {
					self.fetchMealPlans()
				}
			} catch {
				print("Create meal plan error: \(error)")
			}
		}
	}

	func updateMealPlan(for dateString: String, meal: String) {
		guard var existingPlan = mealPlans[dateString] else { return }
		existingPlan.mealDescription = meal
		mealPlans[dateString] = existingPlan

		guard let url = URL(string: "https://ls.jsinha.com/api/meal-plans/\(existingPlan.id)") else {
			return
		}
		var request = URLRequest(url: url)
		request.httpMethod = "PUT"
		request.httpBody = try? JSONEncoder().encode(existingPlan)
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")

		let client = NetworkClient()

		Task {
			do {
				let (_, response) = try await client.send(request)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					print("Server returned status \(http.statusCode)")
					await MainActor.run {
						self.fetchMealPlans()
					}
				}
			} catch {
				print("Update meal plan error: \(error)")
				await MainActor.run {
					self.fetchMealPlans()
				}
			}
		}
	}


	func deleteMealPlan(mealId: String) {
		// Optimistically remove locally
		self.removeMealPlan(withId: mealId)
		guard let url = URL(string: "https://ls.jsinha.com/api/meal-plans/\(mealId)") else {
			return
		}
		var request = URLRequest(url: url)
		request.httpMethod = "DELETE"

		let client = NetworkClient()

		Task {
			do {
				let (_, response) = try await client.send(request)
				if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
					print("Server returned status \(http.statusCode)")
					await MainActor.run {
						self.fetchMealPlans()
					}
				}
			} catch {
				print("Delete meal plan error: \(error)")
				await MainActor.run {
					self.fetchMealPlans()
				}
			}
		}
	}

	static func utcDateString(for date: Date) -> String {
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
