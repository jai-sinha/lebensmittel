import SwiftUI
import Combine

struct MealPlanEntry: Equatable {
    let id: String
    let meal: String
}

class MealsModel: ObservableObject {
    @Published var baseDate: Date
    @Published var mealPlans: [String: MealPlanEntry] = [:]
    
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
            DispatchQueue.main.async {
                self.mealPlans.removeAll()
                for item in json {
                    if let id = item["id"] as? String,
                       let dateStr = item["date"] as? String,
                       let meal = item["mealDescription"] as? String {
                        self.mealPlans[dateStr] = MealPlanEntry(id: id, meal: meal)
                    }
                }
            }
        }.resume()
    }
    
    func getMealPlan(for dateString: String) -> String {
        return mealPlans[dateString]?.meal ?? ""
    }
    
    func mealPlanId(for dateString: String) -> String? {
        return mealPlans[dateString]?.id
    }
    
    func createMealPlan(for dateString: String, meal: String) {
        guard let url = URL(string: "http://192.168.2.113:8000/api/meal-plans") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = ["date": dateString, "mealDescription": meal]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = item["id"] as? String,
                  let dateStr = item["date"] as? String else { return }
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
