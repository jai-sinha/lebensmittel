import SwiftUI

struct GroceriesView: View {
    @ObservedObject var appData: AppData
    @State private var newItemName = ""
    @State private var selectedCategory = "Other"
    @State private var showingAddItem = false
    @State private var isSearching = false
    @State private var expandedCategories: Set<String> = []
    // API state
    @State private var groceryItems: [GroceryItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    
    private let categories = ["Vegetables", "Protein", "Fruit", "Bread", "Beverages", "Other", "Essentials"]
    
    // Computed property for search results
    private var searchResults: [GroceryItem] {
        guard !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let searchTerm = newItemName.lowercased()
        return groceryItems.filter { item in
            item.name.lowercased().contains(searchTerm)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var exactMatch: GroceryItem? {
        let trimmedName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        return groceryItems.first {
            $0.name.lowercased() == trimmedName.lowercased()
        }
    }
    
    // Group items by category
    private var itemsByCategory: [String: [GroceryItem]] {
        Dictionary(grouping: groceryItems) { $0.category }
    }
    
    // Get sorted categories (with items first, then empty categories)
    private var sortedCategories: [String] {
        let categoriesWithItems = itemsByCategory.keys.sorted()
        let emptycategories = categories.filter { !itemsByCategory.keys.contains($0) }
        return categoriesWithItems + emptycategories
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading groceries...")
                } else if let errorMessage = errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red)
                } else {
                    List {
                        ForEach(sortedCategories, id: \.self) { category in
                            if let items = itemsByCategory[category], !items.isEmpty {
                                CategorySection(
                                    category: category,
                                    items: items,
                                    isExpanded: expandedCategories.contains(category),
                                    onToggleExpansion: {
                                        if expandedCategories.contains(category) {
                                            expandedCategories.remove(category)
                                        } else {
                                            expandedCategories.insert(category)
                                        }
                                    },
                                    onToggleNeeded: { item, isNeeded in
                                        updateGroceryItemNeeded(item: item, isNeeded: isNeeded)
                                    },
                                    onDelete: { item in
                                        deleteGroceryItem(item: item)
                                    }
                                )
                            }
                        }
                    }
                    
                    VStack(spacing: 0) {
                        // Search results dropdown
                        if isSearching && !searchResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(searchResults.prefix(5)) { item in
                                    Button(action: {
                                        selectExistingItem(item)
                                    }) {
                                        HStack {
                                            Image(systemName: item.isNeeded ? "checkmark.square.fill" : "square")
                                                .foregroundColor(item.isNeeded ? .green : .gray)
                                            
                                            VStack(alignment: .leading) {
                                                Text(item.name)
                                                    .foregroundColor(.primary)
                                                Text(item.category)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if !item.isNeeded {
                                                Text("Add to list")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .background(Color(.systemGray6))
                                    
                                    if item.id != searchResults.prefix(5).last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        
                        VStack(spacing: 8) {
                            // Category picker
                            HStack {
                                Text("Category:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Picker("Category", selection: $selectedCategory) {
                                    ForEach(categories, id: \.self) { category in
                                        Text(category).tag(category)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            
                            // Search/Add field
                            HStack {
                                TextField("Search or add new item", text: $newItemName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: newItemName) { _ in
                                        isSearching = !newItemName.isEmpty
                                    }
                                    .onSubmit {
                                        addItem()
                                    }
                                
                                Button(exactMatch != nil ? "Select" : "Add") {
                                    addItem()
                                }
                                .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                }
            }
            .navigationTitle("Groceries")
            .onAppear {
                fetchGroceries()
                // Expand all categories by default
                expandedCategories = Set(sortedCategories)
            }
        }
    }
    
    private func addItem() {
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
    
    private func selectExistingItem(_ item: GroceryItem) {
        if !item.isNeeded {
            updateGroceryItemNeeded(item: item, isNeeded: true)
        }
        newItemName = ""
        isSearching = false
    }
    
    // API: Fetch grocery items
    private func fetchGroceries() {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else {
                    errorMessage = "No data received"
                    return
                }
                do {
                    let response = try JSONDecoder().decode(GroceryItemsResponse.self, from: data)
                    groceryItems = response.groceryItems
                } catch {
                    errorMessage = "Failed to decode items: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    // API: Create grocery item
    private func createGroceryItem(name: String, category: String) {
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
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    fetchGroceries()
                }
            }
        }.resume()
    }
    // API: Update grocery item isNeeded
    private func updateGroceryItemNeeded(item: GroceryItem, isNeeded: Bool) {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items/\(item.id)") else {
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
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    fetchGroceries()
                }
            }
        }.resume()
    }
    // API: Delete grocery item
    private func deleteGroceryItem(item: GroceryItem) {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://192.168.2.113:8000/api/grocery-items/\(item.id)") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error {
                    errorMessage = error.localizedDescription
                } else {
                    fetchGroceries()
                }
            }
        }.resume()
    }
}

// Response struct for grocery items API
private struct GroceryItemsResponse: Decodable {
    let count: Int
    let groceryItems: [GroceryItem]
}

struct CategorySection: View {
    let category: String
    let items: [GroceryItem]
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    let onToggleNeeded: (GroceryItem, Bool) -> Void
    let onDelete: (GroceryItem) -> Void
    
    var body: some View {
        Section {
            if isExpanded {
                ForEach(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                    HStack {
                        Button(action: {
                            onToggleNeeded(item, !item.isNeeded)
                        }) {
                            Image(systemName: item.isNeeded ? "checkmark.square" : "square")
                                .foregroundColor(item.isNeeded ? .green : .gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Text(item.name)
                            .foregroundColor(item.isNeeded ? .primary : .gray)
                        
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { offsets in
                    let sortedItems = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    for index in offsets {
                        onDelete(sortedItems[index])
                    }
                }
            }
        } header: {
            Button(action: onToggleExpansion) {
                HStack {
                    Text(category)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(items.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

#Preview {
    GroceriesView(appData: AppData())
}
