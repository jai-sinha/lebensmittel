//
//  MealsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct MealsView: View {
	@Environment(MealsModel.self) var model
	@Environment(\.colorScheme) var colorScheme
	@State private var mealTexts: [String: String] = [:]
	@State private var hasGroups: Bool = true

	private func date(for dayOffset: Int) -> Date {
		Calendar.current.date(byAdding: .day, value: dayOffset, to: model.baseDate)
			?? model.baseDate
	}

	private func isToday(utcDate: Date) -> Bool {
		let calendar = Calendar.current
		let today = Date()
		return calendar.isDate(utcDate, inSameDayAs: today)
	}

	var body: some View {
		NavigationStack {
			ZStack {
				if !hasGroups {
					Text("Please create or join a group to start meal planning.")
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background(Color(.systemBackground))
				} else {
					(colorScheme == .dark
						? Color(.systemBackground) : Color(.secondarySystemBackground))
						.ignoresSafeArea()
					ScrollViewReader { proxy in
						ScrollView {
							VStack(spacing: -4) {
								// Past days (scrollable up)
								ForEach(-7..<0, id: \.self) { dayOffset in
									let rowDate = date(for: dayOffset)
									let dateStr = MealsModel.utcDateString(for: rowDate)
									MealRowView(
										date: rowDate,
										text: Binding(
											get: { mealTexts[dateStr] ?? model.getMealPlan(for: dateStr) },
											set: { mealTexts[dateStr] = $0 }
										)
									)
								}
								// Current day and next 6 days (the main 7-day view)
								ForEach(0..<7, id: \.self) { dayOffset in
									let rowDate = date(for: dayOffset)
									let dateStr = MealsModel.utcDateString(for: rowDate)
									let isThisToday = isToday(utcDate: rowDate)
									MealRowView(
										date: rowDate,
										text: Binding(
											get: { mealTexts[dateStr] ?? model.getMealPlan(for: dateStr) },
											set: { mealTexts[dateStr] = $0 }
										)
									)
									.id(isThisToday ? "today" : "day_\(dayOffset)")
								}
								// Future days (scrollable down)
								ForEach(7..<10, id: \.self) { dayOffset in
									let rowDate = date(for: dayOffset)
									let dateStr = MealsModel.utcDateString(for: rowDate)
									MealRowView(
										date: rowDate,
										text: Binding(
											get: { mealTexts[dateStr] ?? model.getMealPlan(for: dateStr) },
											set: { mealTexts[dateStr] = $0 }
										)
									)
								}
							}
							.padding(.horizontal)
						}
						.onAppear {
							proxy.scrollTo("today", anchor: .top)
						}
					}
					.onChange(of: model.mealPlans) {
						// Remove keys from mealTexts that are no longer in mealPlans
						mealTexts = mealTexts.filter { model.mealPlans.keys.contains($0.key) }
						// Update or add descriptions for existing keys
						for (date, plan) in model.mealPlans {
							mealTexts[date] = plan.mealDescription
						}
					}
				}
			}
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Meal Planning")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					AuthMenuView()
				}
			}
			.task {
				do {
					let groups = try await AuthManager.shared.getUserGroups()
					hasGroups = !groups.isEmpty
				} catch {
					print("Error checking groups: \(error)")
				}
			}
		}
	}
}

struct MealRowView: View {
	let date: Date
	@Binding var text: String

	@Environment(MealsModel.self) var model

	private var dateStr: String {
		MealsModel.utcDateString(for: date)
	}

	private var isTodayDate: Bool {
		Calendar.current.isDate(date, inSameDayAs: Date())
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				HStack(spacing: 4) {
					Text(model.dayFormatter.string(from: date))
						.font(.title2)
						.foregroundStyle(isTodayDate ? .blue.opacity(0.8) : .secondary)
					Text(model.dateFormatter.string(from: date))
						.font(.title2)
						.foregroundStyle(isTodayDate ? .blue : .primary)
				}
				Spacer()
				if isTodayDate {
					Text("Today")
						.font(.caption)
						.foregroundStyle(.blue)
						.padding(.horizontal, 8)
						.padding(.vertical, 4)
						.background(Color.blue.opacity(0.1))
						.clipShape(.rect(cornerRadius: 8))
				}
			}
			TextField(
				"",
				text: $text
			)
			.textFieldStyle(RoundedBorderTextFieldStyle())
			.foregroundStyle(.primary)
			.submitLabel(.done)
			.onSubmit {
				handleSubmit()
			}
		}
		.padding(.vertical, 4)
		.padding(.horizontal, 8)
		.padding(.vertical, 2)
	}

	private func handleSubmit() {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.isEmpty {
			if let mealId = model.mealPlanId(for: dateStr) {
				model.deleteMealPlan(mealId: mealId)
			}
		} else if let _ = model.mealPlanId(for: dateStr) {
			model.updateMealPlan(for: dateStr, meal: trimmed)
		} else {
			model.createMealPlan(for: dateStr, meal: trimmed)
		}
	}
}
#Preview {
	MealsView()
}
