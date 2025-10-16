import Foundation
import Combine

class GroceriesModel: ObservableObject {
    @Published var groceryItems: [GroceryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var newItemName: String = ""
    @Published var selectedCategory: String = "Other"
    @Published var expandedCategories: Set<String> = []
    @Published var isSearching: Bool = false

    let categories = ["Vegetables", "Protein", "Fruit", "Bread", "Beverages", "Other", "Essentials"]

    var searchResults: [GroceryItem] {
        guard !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let searchTerm = newItemName.lowercased()
        return groceryItems.filter { item in
            item.name.lowercased().contains(searchTerm)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var exactMatch: GroceryItem? {
        let trimmedName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        return groceryItems.first {
            $0.name.lowercased() == trimmedName.lowercased()
        }
    }

    var itemsByCategory: [String: [GroceryItem]] {
        Dictionary(grouping: groceryItems) { $0.category }
    }

    var sortedCategories: [String] {
        let categoriesWithItems = itemsByCategory.keys.sorted()
        let emptycategories = categories.filter { !itemsByCategory.keys.contains($0) }
        return categoriesWithItems + emptycategories
    }

    func addItem() {
        let trimmedName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            if let existingItem = groceryItems.first(where: {
                $0.name.lowercased() == trimmedName.lowercased()
            }) {
                if !existingItem.isNeeded {
                    updateGroceryItemNeeded(item: existingItem, isNeeded: true)
                }
            } else {
                createGroceryItem(name: trimmedName, category: selectedCategory)
                expandedCategories.insert(selectedCategory)
            }
            newItemName = ""
            isSearching = false
        }
    }

    func selectExistingItem(_ item: GroceryItem) {
        if !item.isNeeded {
            updateGroceryItemNeeded(item: item, isNeeded: true)
        }
        newItemName = ""
        isSearching = false
    }

    func fetchGroceries() {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else {
                    self.errorMessage = "No data"
                    return
                }
                do {
                    let response = try JSONDecoder().decode(GroceryItemsResponse.self, from: data)
                    self.groceryItems = response.groceryItems
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }.resume()
    }

    func createGroceryItem(name: String, category: String) {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let newItem: [String: Any] = ["name": name, "category": category, "isNeeded": true, "isShoppingChecked": false]
        request.httpBody = try? JSONSerialization.data(withJSONObject: newItem)
        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.fetchGroceries()
                }
            }
        }.resume()
    }

    func updateGroceryItemNeeded(item: GroceryItem, isNeeded: Bool) {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items/\(item.id.uuidString.lowercased())") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let updatedItem: [String: Any] = ["name": item.name, "category": item.category, "isNeeded": isNeeded, "isShoppingChecked": item.isShoppingChecked]
        request.httpBody = try? JSONSerialization.data(withJSONObject: updatedItem)
        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.fetchGroceries()
                }
            }
        }.resume()
    }

    func deleteGroceryItem(item: GroceryItem) {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items/\(item.id.uuidString.lowercased())") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.fetchGroceries()
                }
            }
        }.resume()
    }
}
