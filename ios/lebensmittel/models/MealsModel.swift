//
//  MealsModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//

import SwiftUI
import Combine
import Foundation

// Use MealPlan from Models.swift
class MealsModel: ObservableObject {
    @Published var baseDate: Date
    @Published var mealPlans: [String: MealPlan] = [:] // Keyed by date string
    
    init(baseDate: Date = Calendar.current.startOfDay(for: Date())) {
        self.baseDate = baseDate
    }
    
    func fetchMealPlans() {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data else {
                print("Failed to fetch meal plans data")
                return
            }
            Task {
                do {
                    let response = try JSONDecoder().decode(MealPlansResponse.self, from: data)
                    await MainActor.run {
                        self.mealPlans.removeAll()
                        for mealPlan in response.mealPlans {
                            self.mealPlans[mealPlan.date] = mealPlan
                        }
                    }
                } catch {
                    print("Decoding error: \(error)")
                }
            }
        }.resume()
    }
    
    func getMealPlan(for dateString: String) -> String {
        return mealPlans[dateString]?.mealDescription ?? ""
    }
    
    func mealPlanId(for dateString: String) -> String? {
        return mealPlans[dateString]?.id
    }
    
    func createMealPlan(for dateString: String, meal: String) {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let newMealPlan = NewMealPlan(date: dateString, mealDescription: meal)
        request.httpBody = try? JSONEncoder().encode(newMealPlan)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.fetchMealPlans()
            }
        }.resume()
    }
    
    func deleteMealPlan(mealId: String) {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans/\(mealId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.fetchMealPlans()
            }
        }.resume()
    }
    
    static func utcDateString(for date: Date) -> String {
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
