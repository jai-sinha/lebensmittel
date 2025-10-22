//
//  GroceriesModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/16/25.
//


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
    
    // MARK: UI Update Methods
    
    func addItem(_ item: GroceryItem) {
        DispatchQueue.main.async {
            self.groceryItems.append(item)
        }
    }
    
    func updateItem(_ updatedItem: GroceryItem) {
        DispatchQueue.main.async {
            if let index = self.groceryItems.firstIndex(where: { $0.id == updatedItem.id }) {
                self.groceryItems[index] = updatedItem
            }
        }
    }
    
    func removeItem(withId id: String) {
        DispatchQueue.main.async {
            self.groceryItems.removeAll { $0.id == id }
        }
    }
    
    // MARK: CRUD Methods

    func fetchGroceries() {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(GroceryItemsResponse.self, from: data)
                DispatchQueue.main.async {
                    self.groceryItems = response.groceryItems
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func createGroceryItem(name: String, category: String) {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        let newItem = NewGroceryItem(name: name, category: category)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(newItem)
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    await MainActor.run {
                        self.errorMessage = "Server returned status \(http.statusCode)"
                    }
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        self.fetchGroceries()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func updateGroceryItemNeeded(item: GroceryItem, isNeeded: Bool) {
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items/\(item.id)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        // Optimistically update locally
        var updatedItem = item
        updatedItem.isNeeded = isNeeded
        updateItem(updatedItem)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["isNeeded": isNeeded])
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    await MainActor.run {
                        self.errorMessage = "Server returned status \(http.statusCode)"
                        self.fetchGroceries()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.fetchGroceries()
                }
            }
        }
    }

    func deleteGroceryItem(item: GroceryItem) {
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items/\(item.id)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        // Optimistically remove locally so UI updates immediately
        let removedId = item.id
        removeItem(withId: removedId)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    await MainActor.run {
                        self.errorMessage = "Server returned status \(http.statusCode)"
                        self.fetchGroceries()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.fetchGroceries()
                }
            }
        }
    }
}
