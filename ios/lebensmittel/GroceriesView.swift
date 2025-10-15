import SwiftUI

struct GroceriesView: View {
    @ObservedObject var appData: AppData
    @State private var newItemName = ""
    @State private var selectedCategory = "Other"
    @State private var showingAddItem = false
    @State private var isSearching = false
    @State private var expandedCategories: Set<String> = []
    
    // Predefined categories
    private let categories = ["Vegetables", "Protein", "Fruit", "Bread", "Beverages", "Other", "Essentials"]
    
    // Computed property for search results
    private var searchResults: [GroceryItem] {
        guard !newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let searchTerm = newItemName.lowercased()
        return appData.groceryItems.filter { item in
            item.name.lowercased().contains(searchTerm)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    private var exactMatch: GroceryItem? {
        let trimmedName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        return appData.groceryItems.first {
            $0.name.lowercased() == trimmedName.lowercased()
        }
    }
    
    // Group items by category
    private var itemsByCategory: [String: [GroceryItem]] {
        Dictionary(grouping: appData.groceryItems) { $0.category }
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
                List {
                    ForEach(sortedCategories, id: \.self) { category in
                        if let items = itemsByCategory[category], !items.isEmpty {
                            CategorySection(
                                category: category,
                                items: items,
                                isExpanded: expandedCategories.contains(category),
                                appData: appData,
                                onToggleExpansion: {
                                    if expandedCategories.contains(category) {
                                        expandedCategories.remove(category)
                                    } else {
                                        expandedCategories.insert(category)
                                    }
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
            .navigationTitle("Groceries")
            .onAppear {
                // Expand all categories by default
                expandedCategories = Set(sortedCategories)
            }
        }
    }
    
    private func addItem() {
        let trimmedName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            // Check if item already exists (case-insensitive)
            if let existingItem = appData.groceryItems.first(where: {
                $0.name.lowercased() == trimmedName.lowercased()
            }) {
                // If item exists, make sure it's marked as needed
                if !existingItem.isNeeded {
                    appData.toggleGroceryItemNeeded(item: existingItem)
                }
            } else {
                // Only create new item if it doesn't exist
                appData.addGroceryItem(trimmedName, category: selectedCategory)
                // Expand the category if it's not already expanded
                expandedCategories.insert(selectedCategory)
            }
            newItemName = ""
            isSearching = false
        }
    }
    
    private func selectExistingItem(_ item: GroceryItem) {
        // If the item isn't marked as needed, mark it as needed
        if !item.isNeeded {
            appData.toggleGroceryItemNeeded(item: item)
        }
        // Clear the search field and hide search results
        newItemName = ""
        isSearching = false
    }
}

struct CategorySection: View {
    let category: String
    let items: [GroceryItem]
    let isExpanded: Bool
    let appData: AppData
    let onToggleExpansion: () -> Void
    
    var body: some View {
        Section {
            if isExpanded {
                ForEach(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                    HStack {
                        Button(action: {
                            appData.toggleGroceryItemNeeded(item: item)
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
                        appData.deleteGroceryItem(item: sortedItems[index])
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
