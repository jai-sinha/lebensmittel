import SwiftUI
import Combine

struct MealPlanEntry: Equatable {
    let id: String
    let meal: String
}

class MealsModel: ObservableObject {
    @Published var baseDate: Date
    @Published var mealPlans: [Date: MealPlanEntry] = [:]
    
    init(baseDate: Date = Calendar.current.startOfDay(for: Date())) {
        self.baseDate = baseDate
    }
    
    func fetchMealPlans() {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let json = root["mealPlans"] as? [[String: Any]] else {
                print("Failed to fetch or parse meal plans data")
                return
            }
            print("Fetched meal plans JSON: \(json)") // Print the raw JSON results
            DispatchQueue.main.async {
                for item in json {
                    if let id = item["id"] as? String,
                       let dateStr = item["date"] as? String,
                       let meal = item["mealDescription"] as? String,
                       let date = self.dateFromString(dateStr) {
                        let normalizedDate = Calendar.current.startOfDay(for: date)
                        self.mealPlans[normalizedDate] = MealPlanEntry(id: id, meal: meal)
                    }
                }
            }
        }.resume()
    }
    
    func getMealPlan(for date: Date) -> String {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        return mealPlans[normalizedDate]?.meal ?? ""
    }
    
    func mealPlanId(for date: Date) -> String? {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        return mealPlans[normalizedDate]?.id
    }
    
    func createMealPlan(for date: Date, meal: String) {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["date": stringFromDate(date), "mealDescription": meal]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = item["id"] as? String,
                  let dateStr = item["date"] as? String,
                  let responseDate = self.dateFromString(dateStr) else { return }
            let normalizedDate = Calendar.current.startOfDay(for: responseDate)
            DispatchQueue.main.async {
                self.mealPlans[normalizedDate] = MealPlanEntry(id: id, meal: meal)
            }
        }.resume()
    }
    
    func updateMealPlan(mealId: String, for date: Date, meal: String) {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans/\(mealId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        let body: [String: Any] = ["date": stringFromDate(date), "mealDescription": meal]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dateStr = item["date"] as? String,
                  let responseDate = self.dateFromString(dateStr) else { return }
            let normalizedDate = Calendar.current.startOfDay(for: responseDate)
            DispatchQueue.main.async {
                self.mealPlans[normalizedDate] = MealPlanEntry(id: mealId, meal: meal)
            }
        }.resume()
    }
    
    func deleteMealPlan(mealId: String, for date: Date) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans/\(mealId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.mealPlans.removeValue(forKey: normalizedDate)
            }
        }.resume()
    }
    
    func date(for dayOffset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? Date()
    }
    
    func dayLabel(for date: Date, dayOffset: Int) -> String {
        let day = dayFormatter.string(from: date)
        let dateStr = dateFormatter.string(from: date)
        if dayOffset == 0 {
            return "\(day) \(dateStr) (Today)"
        } else {
            return "\(day) \(dateStr)"
        }
    }
    
    private func stringFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: string)
    }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }
    
    var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }
}
