//
//  MealsModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import Foundation

@MainActor
@Observable
class MealsModel {
	private let service: any MealsServicing
	var mealPlans: [String: MealPlan] = [:]  // Keyed by date string
	var errorMessage: String? = nil

	init(service: any MealsServicing = MealsService()) {
		self.service = service
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
		errorMessage = nil

		if !ConnectivityMonitor.shared.isOnline {
			let localPlans = SyncEngine.shared.loadAllMealPlans()
			self.mealPlans.removeAll()
			for mealPlan in localPlans {
				self.mealPlans[mealPlan.date] = mealPlan
			}
			return
		}

		Task {
			do {
				let mealPlans = try await service.fetchMealPlans()
				let mergedPlans = SyncEngine.shared.mergeMealPlans(mealPlans)
				self.mealPlans.removeAll()
				for mealPlan in mergedPlans {
					self.mealPlans[mealPlan.date] = mealPlan
				}
			} catch {
				self.errorMessage = UserFacingError.message(for: error)
			}
		}
	}

	func createMealPlan(for dateString: String, meal: String) {
		errorMessage = nil

		let createdPlan = SyncEngine.shared.enqueueMealCreate(
			date: dateString,
			mealDescription: meal
		)
		mealPlans[createdPlan.date] = createdPlan
	}

	func updateMealPlan(for dateString: String, meal: String) {
		guard let existingPlan = mealPlans[dateString] else { return }
		if existingPlan.mealDescription == meal { return }  // No change, skip update

		errorMessage = nil

		if let updatedPlan = SyncEngine.shared.enqueueMealUpdate(
			mealID: existingPlan.id,
			mealDescription: meal,
			snapshot: existingPlan
		) {
			mealPlans[updatedPlan.date] = updatedPlan
		}
	}

	func deleteMealPlan(mealId: String) {
		errorMessage = nil

		SyncEngine.shared.enqueueMealDelete(mealID: mealId)
		removeMealPlan(withId: mealId)
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
