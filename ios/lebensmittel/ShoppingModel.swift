import Foundation
import Combine

class ShoppingModel: ObservableObject {
    @Published var shoppingItems: [GroceryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    var uncheckedItems: [GroceryItem] {
        return shoppingItems.filter { !$0.isShoppingChecked }
    }
    
    var checkedItems: [GroceryItem] {
        return shoppingItems.filter { $0.isShoppingChecked }
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
        let updatedItem: [String: Any] = ["name": item.name, "category": item.category, "isNeeded": item.isNeeded, "isShoppingChecked": isChecked]
        request.httpBody = try? JSONSerialization.data(withJSONObject: updatedItem)
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
}
