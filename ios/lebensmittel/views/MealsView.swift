//
//  MealsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct MealsView: View {
    @StateObject private var model = MealsModel()
    @State private var mealTexts: [String: String] = [:]
    
    private func date(for dayOffset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: model.baseDate) ?? model.baseDate
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
                        model.fetchMealPlans()
                        DispatchQueue.main.async {
                            proxy.scrollTo("today", anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: model.mealPlans) {
                for (dateStr, plan) in model.mealPlans {
                    mealTexts[dateStr] = plan.mealDescription
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Meal Planning")
        }
    }
    
    private func mealRowView(for date: Date, dayOffset: Int) -> some View {
        let dateStr = MealsModel.utcDateString(for: date)
        let isTodayDate = isToday(utcDate: date)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(model.dayFormatter.string(from: date))
                        .font(.title2)
                        .foregroundColor(isTodayDate ? .blue.opacity(0.8) : .secondary)
                    Text(model.dateFormatter.string(from: date))
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
                get: { mealTexts[dateStr] ?? model.getMealPlan(for: dateStr) },
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
                    if let mealId = model.mealPlanId(for: dateStr) {
                        model.deleteMealPlan(mealId: mealId)
                    }
                } else {
                    model.createMealPlan(for: dateStr, meal: text)
                }
            }
            Divider()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MealsView()
}
