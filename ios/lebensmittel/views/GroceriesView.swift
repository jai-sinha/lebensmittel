//
//  GroceriesView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct GroceriesView: View {
    @EnvironmentObject var model: GroceriesModel
    
    var body: some View {
        NavigationView {
            VStack {
                if model.isLoading {
                    ProgressView("Loading groceries...")
                } else if let errorMessage = model.errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red)
                } else {
                    HStack(spacing: 0) {
                        // Essentials pane (left)
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Essentials")
                                    .font(.headline)
                                    .padding(.bottom, 4)
                                if !model.essentialsItems.isEmpty {
                                    ForEach(model.essentialsItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                                        HStack {
                                            Button(action: {
                                                model.updateGroceryItem(item: item, field: .isNeeded(!item.isNeeded))
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
                                } else {
                                    Text("No Essentials")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()
                            .frame(width: 1)
                            .background(Color(.systemGray4))
                            .padding(.vertical)

                        // Other categories pane (right)
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(model.otherCategories, id: \ .self) { category in
                                    if let items = model.itemsByCategory[category], !items.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            // Collapsible header
                                            Button(action: {
                                                if model.expandedCategories.contains(category) {
                                                    model.expandedCategories.remove(category)
                                                } else {
                                                    model.expandedCategories.insert(category)
                                                }
                                            }) {
                                                HStack {
                                                    Text(category)
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Image(systemName: model.expandedCategories.contains(category) ? "chevron.down" : "chevron.right")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            // Show items if expanded
                                            if model.expandedCategories.contains(category) {
                                                ForEach(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                                                    HStack {
                                                        Button(action: {
                                                            model.updateGroceryItem(item: item, field: .isNeeded(!item.isNeeded))
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
                                            }
                                        }
                                        .padding()
                                        .background(Color(.systemGray6))
                                        .cornerRadius(12)
                                    }
                                }
                            }
                            .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Groceries")
            .onAppear {
                model.fetchGroceries()
                model.expandedCategories = Set(model.sortedCategories)
            }
        }
    }
}

struct CategorySection: View {
    @EnvironmentObject var model: GroceriesModel
    let category: String
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    let onToggleNeeded: (GroceryItem, Bool) -> Void
    let onDelete: (GroceryItem) -> Void

    var body: some View {
        Section {
            if isExpanded {
                let items = model.itemsByCategory[category] ?? []
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
                    Text("\( (model.itemsByCategory[category] ?? []).count )")
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
