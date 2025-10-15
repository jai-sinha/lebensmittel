//
//  MealsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct MealsView: View {
    @ObservedObject var appData: AppData
    @State private var baseDate = Calendar.current.startOfDay(for: Date())
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: -4) {
                        // Past days (scrollable up)
                        ForEach(-30..<0, id: \.self) { dayOffset in
                            mealRowView(for: Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? Date(), dayOffset: dayOffset)
                        }
                        
                        // Current day and next 6 days (the main 7-day view)
                        ForEach(0..<7, id: \.self) { dayOffset in
                            mealRowView(for: Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? Date(), dayOffset: dayOffset)
                                .id(dayOffset == 0 ? "today" : "day_\(dayOffset)")
                        }
                        
                        // Future days (scrollable down)
                        ForEach(7..<37, id: \.self) { dayOffset in
                            mealRowView(for: Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? Date(), dayOffset: dayOffset)
                        }
                    }
                    .padding(.horizontal)
                }
                .onAppear {
                    // Scroll to today when view appears with a slight delay to ensure content is rendered
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo("today", anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle("Meal Planning")
        }
    }
    
    private func mealRowView(for date: Date, dayOffset: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(dayFormatter.string(from: date))
                        .font(.title2)
                        .foregroundColor(dayOffset == 0 ? .blue.opacity(0.8) : .secondary)
                    
                    Text(dateFormatter.string(from: date))
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
                get: { appData.getMealPlan(for: date) },
                set: { newValue in appData.updateMealPlan(for: date, meal: newValue) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .submitLabel(.done)
            
            Divider()
        }
        .padding(.vertical, 4)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }
}

#Preview {
    MealsView(appData: AppData())
}
