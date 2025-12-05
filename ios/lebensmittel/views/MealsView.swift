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
		NavigationView {
			ZStack {
				(colorScheme == .dark
					? Color(.systemBackground) : Color(.secondarySystemBackground))
					.ignoresSafeArea()
				VStack {
					ScrollViewReader { proxy in
						ScrollView {
							LazyVStack(spacing: -4) {
								// Past days (scrollable up)
								ForEach(-7..<0, id: \.self) { dayOffset in
									mealRowView(for: date(for: dayOffset), dayOffset: dayOffset)
								}
								// Current day and next 6 days (the main 7-day view)
								ForEach(0..<7, id: \.self) { dayOffset in
									let rowDate = date(for: dayOffset)
									let isThisToday = isToday(utcDate: rowDate)
									mealRowView(for: rowDate, dayOffset: dayOffset)
										.id(isThisToday ? "today" : "day_\(dayOffset)")
								}
								// Future days (scrollable down)
								ForEach(7..<10, id: \.self) { dayOffset in
									mealRowView(for: date(for: dayOffset), dayOffset: dayOffset)
								}
							}
							.padding(.horizontal)
						}
						.onAppear {
							DispatchQueue.main.async {
								proxy.scrollTo("today", anchor: .top)
							}
						}
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
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Meal Planning")
		}
	}

	private func mealRowView(for date: Date, dayOffset: Int) -> some View {
		let dateStr = MealsModel.utcDateString(for: date)
		let isTodayDate = isToday(utcDate: date)
		return VStack(alignment: .leading, spacing: 4) {
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
				text: Binding(
					get: { mealTexts[dateStr] ?? model.getMealPlan(for: dateStr) },
					set: { newValue in
						mealTexts[dateStr] = newValue
					}
				)
			)
			.textFieldStyle(RoundedBorderTextFieldStyle())
			.foregroundStyle(.primary)
			.submitLabel(.done)
			.onSubmit {
				let text = mealTexts[dateStr] ?? ""
				if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					if let mealId = model.mealPlanId(for: dateStr) {
						model.deleteMealPlan(mealId: mealId)
					}
				} else {
					model.createMealPlan(for: dateStr, meal: text)
				}
			}
		}
		.padding(.vertical, 4)
		.padding(.horizontal, 8)
		.padding(.vertical, 2)
	}
}

#Preview {
	MealsView()
}
