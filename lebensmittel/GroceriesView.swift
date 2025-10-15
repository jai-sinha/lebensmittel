//
//  GroceriesView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct GroceriesView: View {
    @ObservedObject var appData: AppData
    @State private var newItemName = ""
    @State private var showingAddItem = false
    @State private var isSearching = false
    
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
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(appData.groceryItems) { item in
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
                    .onDelete(perform: deleteItems)
                }
                
                VStack(spacing: 0) {
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
                    .padding()
                    
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
                                        
                                        Text(item.name)
                                            .foregroundColor(.primary)
                                        
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
                        .padding(.bottom)
                    }
                }
            }
            .navigationTitle("Groceries")
            .toolbar {
                EditButton()
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
                appData.addGroceryItem(trimmedName)
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
    
    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            appData.deleteGroceryItem(item: appData.groceryItems[index])
        }
    }
}

#Preview {
    GroceriesView(appData: AppData())
}
