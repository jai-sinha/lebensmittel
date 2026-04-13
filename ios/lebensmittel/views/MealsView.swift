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
	@Environment(AuthStateManager.self) var authManager
	@FocusState private var focusedMealDate: String?

	private func date(for dayOffset: Int) -> Date {
		let today = Calendar.current.startOfDay(for: Date())
		return Calendar.current.date(byAdding: .day, value: dayOffset, to: today) ?? today
	}

	private func mealDateString(for dayOffset: Int) -> String {
		MealsModel.calendarDateString(for: date(for: dayOffset))
	}

	private func isToday(_ date: Date) -> Bool {
		Calendar.current.isDate(date, inSameDayAs: Date())
	}

	var body: some View {
		NavigationStack {
			ZStack {
				if !authManager.isAuthenticated {
					GuestSignInPrompt(
						message: "Sign in and join a household group to start meal planning."
					)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(Color(.systemBackground))
				} else if authManager.currentUserGroups.isEmpty {
					Text("Please create or join a group to start meal planning.")
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background(Color(.systemBackground))
				} else if let errorMessage = model.errorMessage {
					InlineErrorView(message: errorMessage)
						.refreshable {
							model.errorMessage = nil
							model.fetchMealPlans()
						}
				} else {
					(colorScheme == .dark
						? Color(.systemBackground) : Color(.secondarySystemBackground))
						.ignoresSafeArea()
					ScrollViewReader { proxy in
						ScrollView {
							VStack(spacing: -4) {
								ForEach(-7..<10, id: \.self) { dayOffset in
									let rowDate = date(for: dayOffset)
									mealRow(for: rowDate, dateStr: mealDateString(for: dayOffset))
										.id(isToday(rowDate) ? "today" : "day_\(dayOffset)")
								}
							}
							.padding(.horizontal)
						}
						.scrollDismissesKeyboard(.interactively)
						.refreshable {
							model.errorMessage = nil
							model.fetchMealPlans()
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
			.contentShape(Rectangle())
			.onTapGesture {
				focusedMealDate = nil
			}
			.gesture(
				DragGesture(minimumDistance: 12)
					.onEnded { value in
						if value.translation.height > 20 {
							focusedMealDate = nil
						}
					}
			)
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Meal Planning")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					AuthMenuView()
				}
			}

		}
	}

	@ViewBuilder
	private func mealRow(for rowDate: Date, dateStr: String) -> some View {
		MealRowView(
			date: rowDate,
			text: Binding(
				get: {
					mealTexts[dateStr] ?? model.getMealPlan(for: dateStr)
				},
				set: { mealTexts[dateStr] = $0 }
			),
			focusedMealDate: $focusedMealDate
		)
	}
}

struct MealRowView: View {
	let date: Date
	@Binding var text: String
	@FocusState.Binding var focusedMealDate: String?

	@Environment(MealsModel.self) var model

	private var dateStr: String {
		MealsModel.calendarDateString(for: date)
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
			.focused($focusedMealDate, equals: dateStr)
			.onChange(of: focusedMealDate) {
				if focusedMealDate != dateStr {
					handleSubmit()
				}
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
		} else if model.mealPlanId(for: dateStr) != nil {
			model.updateMealPlan(for: dateStr, meal: trimmed)
		} else {
			model.createMealPlan(for: dateStr, meal: trimmed)
		}
	}
}
