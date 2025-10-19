//
//  GroceriesView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct GroceriesView: View {
    @ObservedObject var appData: AppData
    @StateObject private var model = GroceriesModel()
    
    var body: some View {
        NavigationView {
            VStack {
                if model.isLoading {
                    ProgressView("Loading groceries...")
                } else if let errorMessage = model.errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red)
                } else {
                    List {
                        ForEach(model.sortedCategories, id: \ .self) { category in
                            if let items = model.itemsByCategory[category], !items.isEmpty {
                                CategorySection(
                                    category: category,
                                    items: items,
                                    isExpanded: model.expandedCategories.contains(category),
                                    onToggleExpansion: {
                                        if model.expandedCategories.contains(category) {
                                            model.expandedCategories.remove(category)
                                        } else {
                                            model.expandedCategories.insert(category)
                                        }
                                    },
                                    onToggleNeeded: { item, isNeeded in
                                        model.updateGroceryItemNeeded(item: item, isNeeded: isNeeded)
                                    },
                                    onDelete: { item in
                                        model.deleteGroceryItem(item: item)
                                    }
                                )
                            }
                        }
                    }
                    
                    VStack(spacing: 0) {
                        // Search results dropdown
                        if model.isSearching && !model.searchResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(model.searchResults.prefix(5)) { item in
                                    Button(action: {
                                        model.selectExistingItem(item)
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
                                    if item.id != model.searchResults.prefix(5).last?.id {
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
                                Picker("Category", selection: $model.selectedCategory) {
                                    ForEach(model.categories, id: \ .self) { category in
                                        Text(category).tag(category)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal)
                            
                            // Search/Add field
                            HStack {
                                TextField("Search or add new item", text: $model.newItemName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: model.newItemName) {
                                        model.isSearching = !model.newItemName.isEmpty
                                    }
                                    .onSubmit {
                                        model.addItem()
                                    }
                                Button(model.exactMatch != nil ? "Select" : "Add") {
                                    model.addItem()
                                }
                                .disabled(model.newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                    }
                }
            }
            .navigationTitle("Groceries")
            .onAppear {
                model.fetchGroceries()
                model.expandedCategories = Set(model.sortedCategories)
            }
        }
    }
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
