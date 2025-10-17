//
//  MealsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct MealsView: View {
    @ObservedObject var mealsModel: MealsModel
    @State private var mealTexts: [String: String] = [:]
    
    private func date(for dayOffset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: mealsModel.baseDate) ?? mealsModel.baseDate
    }
    
    private func isToday(utcDate: Date) -> Bool {
        let calendar = Calendar.current
        let today = Date()
        return calendar.isDate(utcDate, inSameDayAs: today)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: -4) {
                            // Past days (scrollable up)
                            ForEach(-30..<0, id: \.self) { dayOffset in
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
                            ForEach(7..<37, id: \.self) { dayOffset in
                                mealRowView(for: date(for: dayOffset), dayOffset: dayOffset)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onAppear {
                        mealsModel.fetchMealPlans()
                        DispatchQueue.main.async {
                            proxy.scrollTo("today", anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: mealsModel.mealPlans) {
                for (dateStr, plan) in mealsModel.mealPlans {
                    mealTexts[dateStr] = plan.meal
                }
            }
            .navigationTitle("Meal Planning")
        }
    }
    
    private func mealRowView(for date: Date, dayOffset: Int) -> some View {
        let dateStr = MealsModel.utcDateString(for: date)
        let isTodayDate = isToday(utcDate: date)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(mealsModel.dayFormatter.string(from: date))
                        .font(.title2)
                        .foregroundColor(isTodayDate ? .blue.opacity(0.8) : .secondary)
                    Text(mealsModel.dateFormatter.string(from: date))
                        .font(.title2)
                        .foregroundColor(isTodayDate ? .blue : .primary)
                }
                Spacer()
                if isTodayDate {
                    Text("Today")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            TextField("", text: Binding(
                get: { mealTexts[dateStr] ?? mealsModel.getMealPlan(for: dateStr) },
                set: { newValue in
                    mealTexts[dateStr] = newValue
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .submitLabel(.done)
            .onSubmit {
                /* if text is empty, and there's an existing meal plan, delete it
                 if text is empty, and no existing meal plan, do nothing
                 if text is non-empty, create meal plan. no update function needed,
                 as backend enforces only one meal item per date.
                */
                let text = mealTexts[dateStr] ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let mealId = mealsModel.mealPlanId(for: dateStr) {
                        mealsModel.deleteMealPlan(mealId: mealId)
                    }
                } else {
                    mealsModel.createMealPlan(for: dateStr, meal: text)
                }
            }
            Divider()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MealsView(mealsModel: MealsModel())
}
