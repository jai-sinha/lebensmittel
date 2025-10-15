//
//  Models.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import Foundation
import Combine

struct GroceryItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var category: String
    var isNeeded: Bool = true // true = need to buy, false = have it
    var isShoppingChecked: Bool = false // checked off in shopping list
}

struct MealPlan: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var mealDescription: String
}

class AppData: ObservableObject {
    @Published var groceryItems: [GroceryItem] = []
    @Published var mealPlans: [MealPlan] = []
    
    private let groceryItemsKey = "groceryItems"
    private let mealPlansKey = "mealPlans"
    
    init() {
        loadData()
    }
    
    func saveData() {
        if let encodedGroceries = try? JSONEncoder().encode(groceryItems) {
            UserDefaults.standard.set(encodedGroceries, forKey: groceryItemsKey)
        }
        
        if let encodedMeals = try? JSONEncoder().encode(mealPlans) {
            UserDefaults.standard.set(encodedMeals, forKey: mealPlansKey)
        }
    }
    
    func loadData() {
        if let data = UserDefaults.standard.data(forKey: groceryItemsKey),
           let decoded = try? JSONDecoder().decode([GroceryItem].self, from: data) {
            groceryItems = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: mealPlansKey),
           let decoded = try? JSONDecoder().decode([MealPlan].self, from: data) {
            mealPlans = decoded
        }
    }
    
    func addGroceryItem(_ name: String, category: String = "Other") {
        let newItem = GroceryItem(name: name, category: category)
        groceryItems.append(newItem)
        saveData()
    }
    
    func toggleGroceryItemNeeded(item: GroceryItem) {
        if let index = groceryItems.firstIndex(where: { $0.id == item.id }) {
            groceryItems[index].isNeeded.toggle()
            // If we now have the item, uncheck it from shopping list too
            if !groceryItems[index].isNeeded {
                groceryItems[index].isShoppingChecked = false
            }
            saveData()
        }
    }
    
    func toggleShoppingItemChecked(item: GroceryItem) {
        if let index = groceryItems.firstIndex(where: { $0.id == item.id }) {
            groceryItems[index].isShoppingChecked.toggle()
            saveData()
        }
    }
    
    func deleteGroceryItem(item: GroceryItem) {
        groceryItems.removeAll { $0.id == item.id }
        saveData()
    }
    
    func updateMealPlan(for date: Date, meal: String) {
        if let index = mealPlans.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
            mealPlans[index].mealDescription = meal
        } else {
            let newMeal = MealPlan(date: date, mealDescription: meal)
            mealPlans.append(newMeal)
        }
        saveData()
    }
    
    func getMealPlan(for date: Date) -> String {
        return mealPlans.first { Calendar.current.isDate($0.date, inSameDayAs: date) }?.mealDescription ?? ""
    }
}
