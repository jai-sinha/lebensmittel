//
//  MealsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct MealsView: View {
    @ObservedObject var appData: AppData
    @State private var baseDate = Date()
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Past days (scrollable up)
                        ForEach(-30..<0, id: \.self) { dayOffset in
                            mealRowView(for: Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? Date(), dayOffset: dayOffset)
                        }
                        
                        // Current day and next 6 days (the main 7-day view)
                        ForEach(0..<7, id: \.self) { dayOffset in
                            mealRowView(for: Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? Date(), dayOffset: dayOffset)
                                .id(dayOffset == 0 ? "today" : nil)
                        }
                        
                        // Future days (scrollable down)
                        ForEach(7..<37, id: \.self) { dayOffset in
                            mealRowView(for: Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? Date(), dayOffset: dayOffset)
                        }
                    }
                    .padding(.horizontal)
                }
                .onAppear {
                    // Scroll to today when view appears
                    withAnimation {
                        proxy.scrollTo("today", anchor: .top)
                    }
                }
            }
            .navigationTitle("Meal Planning")
        }
    }
    
    private func mealRowView(for date: Date, dayOffset: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(dateFormatter.string(from: date))
                        .font(.headline)
                        .foregroundColor(dayOffset == 0 ? .blue : .primary)
                    
                    Text(dayFormatter.string(from: date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
            
            TextField("What's for dinner?", text: Binding(
                get: { appData.getMealPlan(for: date) },
                set: { newValue in appData.updateMealPlan(for: date, meal: newValue) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .submitLabel(.done)
            
            Divider()
        }
        .padding(.vertical, 8)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }
}

#Preview {
    MealsView(appData: AppData())
}