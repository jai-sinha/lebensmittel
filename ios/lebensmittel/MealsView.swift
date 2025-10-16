//
//  MealsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct MealsView: View {
    @ObservedObject var mealsModel: MealsModel
    @State private var mealTexts: [Date: String] = [:]
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: -4) {
                            // Past days (scrollable up)
                            ForEach(-30..<0, id: \.self) { dayOffset in
                                mealRowView(for: mealsModel.date(for: dayOffset), dayOffset: dayOffset)
                            }
                            // Current day and next 6 days (the main 7-day view)
                            ForEach(0..<7, id: \.self) { dayOffset in
                                mealRowView(for: mealsModel.date(for: dayOffset), dayOffset: dayOffset)
                                    .id(dayOffset == 0 ? "today" : "day_\(dayOffset)")
                            }
                            // Future days (scrollable down)
                            ForEach(7..<37, id: \.self) { dayOffset in
                                mealRowView(for: mealsModel.date(for: dayOffset), dayOffset: dayOffset)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onAppear {
                        mealsModel.fetchMealPlans()
                        proxy.scrollTo("today", anchor: .top)
                    }
                }
            }
            .onChange(of: mealsModel.mealPlans) { newPlans in
                // Sync local state with model when mealPlans change
                for (date, plan) in newPlans {
                    mealTexts[date] = plan.meal
                }
            }
            .navigationTitle("Meal Planning")
        }
    }
    
    private func mealRowView(for date: Date, dayOffset: Int) -> some View {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(mealsModel.dayFormatter.string(from: date))
                        .font(.title2)
                        .foregroundColor(dayOffset == 0 ? .blue.opacity(0.8) : .secondary)
                    Text(mealsModel.dateFormatter.string(from: date))
                        .font(.title2)
                        .foregroundColor(dayOffset == 0 ? .blue : .primary)
                }
                Spacer()
                if dayOffset == 0 {
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
                get: { mealTexts[normalizedDate] ?? mealsModel.getMealPlan(for: date) },
                set: { newValue in
                    mealTexts[normalizedDate] = newValue
                }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .submitLabel(.done)
            .onSubmit {
                let text = mealTexts[normalizedDate] ?? ""
                if let mealId = mealsModel.mealPlanId(for: date) {
                    mealsModel.updateMealPlan(mealId: mealId, for: date, meal: text)
                } else {
                    mealsModel.createMealPlan(for: date, meal: text)
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
