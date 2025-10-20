//
//  ShoppingModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/17/25.
//

import Foundation
import Combine

class ShoppingModel: ObservableObject {
    @Published var shoppingItems: [GroceryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    var uncheckedItems: [GroceryItem] {
        shoppingItems.filter { !$0.isShoppingChecked }
            .sorted { $0.category < $1.category }
    }
    
    var checkedItems: [GroceryItem] {
        shoppingItems.filter { $0.isShoppingChecked }
            .sorted { $0.category < $1.category }
    }

    func fetchShoppingItems() {
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
                    let neededItems = response.groceryItems.filter { $0.isNeeded }
                    self.shoppingItems = neededItems.sorted { !$0.isShoppingChecked && $1.isShoppingChecked }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }.resume()
    }

    func updateShoppingChecked(item: GroceryItem, isChecked: Bool) {
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
        let updatedItem = UpdateGroceryItem(name: item.name, category: item.category, isNeeded: item.isNeeded, isShoppingChecked: isChecked)
        request.httpBody = try? JSONEncoder().encode(updatedItem)
        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.fetchShoppingItems()
                }
            }
        }.resume()
    }
    
    func createReceipt(price: Double, purchasedBy: String, notes: String) {
        isLoading = true
        errorMessage = nil
        // Format current date as YYYY-MM-DD
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        // Build JSON payload
        let payload: [String: Any] = [
            "date": dateString,
            "totalAmount": price,
            "purchasedBy": purchasedBy,
            "notes": notes
        ]
        guard let url = URL(string: "http://192.168.2.113:8000/api/receipts"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            errorMessage = "Invalid URL or payload"
            isLoading = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self.errorMessage = "Failed to create receipt"
                    return
                }
                self.fetchShoppingItems() // Refresh data after successful receipt creation
            }
        }.resume()
    }
}
