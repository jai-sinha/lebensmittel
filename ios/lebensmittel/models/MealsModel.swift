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
	private let syncEngine: SyncEngine
	var mealPlans: [String: MealPlan] = [:]  // Keyed by date string
	var errorMessage: String? = nil

	init(
		service: any MealsServicing = MealsService(),
		syncEngine: SyncEngine = .shared
	) {
		self.service = service
		self.syncEngine = syncEngine
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
			let localPlans = syncEngine.loadAllMealPlans()
			self.mealPlans.removeAll()
			for mealPlan in localPlans {
				self.mealPlans[mealPlan.date] = mealPlan
			}
			return
		}

		Task {
			do {
				let mealPlans = try await service.fetchMealPlans()
				let mergedPlans = syncEngine.mergeMealPlans(mealPlans)
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

		if !ConnectivityMonitor.shared.isOnline {
			let createdPlan = syncEngine.enqueueMealCreate(
				date: dateString,
				mealDescription: meal
			)
			mealPlans[createdPlan.date] = createdPlan
			return
		}

		Task {
			do {
				_ = try await service.createMealPlan(
					date: dateString,
					mealDescription: meal
				)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
				}
			}
		}
	}

	func updateMealPlan(for dateString: String, meal: String) {
		guard let existingPlan = mealPlans[dateString] else { return }
		if existingPlan.mealDescription == meal { return }  // No change, skip update

		errorMessage = nil

		if !ConnectivityMonitor.shared.isOnline {
			if let updatedPlan = syncEngine.enqueueMealUpdate(
				mealID: existingPlan.id,
				mealDescription: meal
			) {
				mealPlans[updatedPlan.date] = updatedPlan
			}
			return
		}

		Task {
			do {
				try await service.updateMealPlan(
					id: existingPlan.id,
					mealDescription: meal
				)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
				}
			}
		}
	}

	func deleteMealPlan(mealId: String) {
		errorMessage = nil

		if !ConnectivityMonitor.shared.isOnline {
			syncEngine.enqueueMealDelete(mealID: mealId)
			removeMealPlan(withId: mealId)
			return
		}

		Task {
			do {
				try await service.deleteMealPlan(id: mealId)
			} catch {
				await MainActor.run {
					self.errorMessage = UserFacingError.message(for: error)
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
