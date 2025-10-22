//
//  ShoppingModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/17/25.
//

import Foundation
import Combine

class ShoppingModel: GroceriesModel {
    var shoppingItems: [GroceryItem] {
        groceryItems.filter { $0.isNeeded }
    }
    
    var uncheckedItems: [GroceryItem] {
        shoppingItems.filter { !$0.isShoppingChecked }
            .sorted { $0.category < $1.category }
    }
    
    var checkedItems: [GroceryItem] {
        shoppingItems.filter { $0.isShoppingChecked }
            .sorted { $0.category < $1.category }
    }
    
    // Use parent's fetchGroceries for fetching
    // Use parent's updateGroceryItemNeeded and updateItem for updating
    // Use parent's groceryItems for data
    
    func createReceipt(price: Double, purchasedBy: String, notes: String) {
        isLoading = true
        errorMessage = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        let payload = NewReceipt(
            date: dateString,
            totalAmount: price,
            purchasedBy: purchasedBy,
            notes: notes
        )
        guard let url = URL(string: "http://192.168.2.113:8000/api/receipts"),
              let body = try? JSONEncoder().encode(payload) else {
            errorMessage = "Invalid URL or payload"
            isLoading = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    await MainActor.run {
                        self.errorMessage = "Failed to create receipt"
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.fetchGroceries()
                        self.isLoading = false
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
}
