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
	private let syncEngine: SyncEngine
	var mealPlans: [String: MealPlan] = [:]  // Keyed by date string
	var errorMessage: String? = nil

	init(syncEngine: SyncEngine = .shared) {
		self.syncEngine = syncEngine
	}

	func getMealPlan(for dateString: String) -> String {
		return mealPlans[dateString]?.mealDescription ?? ""
	}

	func mealPlanId(for dateString: String) -> UUID? {
		return mealPlans[dateString]?.id
	}

	// MARK: UI Update Methods, used for WebSocket updates

	func addMealPlan(_ plan: MealPlan) {
		if let existingDate = mealPlans.first(where: { $0.value.id == plan.id })?.key,
			existingDate != plan.date
		{
			mealPlans.removeValue(forKey: existingDate)
		}
		mealPlans[plan.date] = plan
	}

	func removeMealPlan(withId id: UUID) {
		if let key = mealPlans.first(where: { $0.value.id == id })?.key {
			mealPlans.removeValue(forKey: key)
		}
	}

	func replaceAll(with plans: [MealPlan]) {
		mealPlans.removeAll()
		for plan in plans {
			mealPlans[plan.date] = plan
		}
	}

	// MARK: CRUD Operations

	func fetchMealPlans() async {
		errorMessage = nil

		guard ConnectivityMonitor.shared.isOnline else { return }

		do {
			try await syncEngine.reconcile(forceSnapshot: true)
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func createMealPlan(for dateString: String, meal: String) {
		errorMessage = nil
		let createdPlan = syncEngine.enqueueMealCreate(date: dateString, mealDescription: meal)
		mealPlans[createdPlan.date] = createdPlan
	}

	func updateMealPlan(for dateString: String, meal: String) {
		guard let existingPlan = mealPlans[dateString] else { return }
		if existingPlan.mealDescription == meal { return }

		errorMessage = nil
		if let updatedPlan = syncEngine.enqueueMealUpdate(mealID: existingPlan.id, mealDescription: meal) {
			mealPlans[updatedPlan.date] = updatedPlan
		}
	}

	func deleteMealPlan(mealId: UUID) {
		errorMessage = nil
		syncEngine.enqueueMealDelete(mealID: mealId)
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
