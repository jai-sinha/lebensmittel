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
    
    func getMealPlan(for dateString: String) -> String {
        return mealPlans[dateString]?.mealDescription ?? ""
    }
    
    func mealPlanId(for dateString: String) -> String? {
        return mealPlans[dateString]?.id
    }
    
    // MARK: UI Update Methods
    
    func addMealPlan(_ plan: MealPlan) {
        DispatchQueue.main.async {
            self.mealPlans[plan.date] = plan
        }
    }
    
    func updateMealPlan(_ plan: MealPlan) {
        DispatchQueue.main.async {
            if var existingPlan = self.mealPlans[plan.date] {
                existingPlan.mealDescription = plan.mealDescription
                self.mealPlans[plan.date] = existingPlan
            }
        }
    }
    
    func removeMealPlan(withId id: String) {
        DispatchQueue.main.async {
            if let key = self.mealPlans.first(where: { $0.value.id == id })?.key {
                self.mealPlans.removeValue(forKey: key)
            }
        }
    }
    
    // MARK: CRUD Methods
    
    func fetchMealPlans() {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans") else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
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
    }
    
    func createMealPlan(for dateString: String, meal: String) {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let newMealPlan = NewMealPlan(date: dateString, mealDescription: meal)
        request.httpBody = try? JSONEncoder().encode(newMealPlan)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    print("Server returned status \(http.statusCode)")
                }
                await MainActor.run {
                    self.fetchMealPlans()
                }
            } catch {
                print("Create meal plan error: \(error)")
            }
        }
    }
    
    func deleteMealPlan(mealId: String) {
        // Optimistically remove locally
        self.removeMealPlan(withId: mealId)
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans/\(mealId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    print("Server returned status \(http.statusCode)")
                    await MainActor.run {
                        self.fetchMealPlans()
                    }
                }
            } catch {
                print("Delete meal plan error: \(error)")
                await MainActor.run {
                    self.fetchMealPlans()
                }
            }
        }
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
