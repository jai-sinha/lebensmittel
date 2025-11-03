//
//  GroceriesView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct GroceriesView: View {
    @EnvironmentObject var model: GroceriesModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            VStack {
                if model.isLoading {
                    ProgressView("Loading groceries...")
                } else if let errorMessage = model.errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red)
                } else {
                    HStack(spacing: 0) {
                        EssentialsPane()
                        Divider()
                            .frame(width: 1)
                            .background(Color(.separator))
                            .padding(.vertical)
                        CategoriesListPane()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 12)
                    // Show search results above the search bar
                    SearchResultsDropdown()
                    AddItemSection()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 0)
                }
            }
            .background(colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Groceries")
            .onAppear {
                model.fetchGroceries()
                model.expandedCategories = Set(model.sortedCategories)
            }
        }
    }
}

struct EssentialsPane: View {
    @EnvironmentObject var model: GroceriesModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        List {
            Section(header:
                Text("Essentials")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 12))
            ) {
                if !model.essentialsItems.isEmpty {
                    ForEach(model.essentialsItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                        GroceryItemRow(item: item)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowSpacing(0)
                            .listRowBackground(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    model.deleteGroceryItem(item: item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 8))
                                }
                            }
                    }
                } else {
                    Text("No Essentials")
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
                }
            }
        }
        .listStyle(PlainListStyle())
        .listRowSpacing(0)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, -10)
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
    }
}

struct CategoriesListPane: View {
    @EnvironmentObject var model: GroceriesModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        List {
            ForEach(model.otherCategories, id: \.self) { category in
                CategoryListSection(category: category)
            }
        }
        .listStyle(PlainListStyle())
        .listRowSpacing(0)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, -16)
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
    }
}

struct CategoryListSection: View {
    @EnvironmentObject var model: GroceriesModel
    @Environment(\.colorScheme) var colorScheme
    let category: String
    
    var body: some View {
        Section(header:
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
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        ) {
            if model.expandedCategories.contains(category), let items = model.itemsByCategory[category], !items.isEmpty {
                ForEach(items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { item in
                    GroceryItemRow(item: item)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowSpacing(0)
                        .listRowBackground(colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.deleteGroceryItem(item: item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 8))
                            }
                        }
                }
            }
        }
    }
}

struct GroceryItemRow: View {
    @EnvironmentObject var model: GroceriesModel
    let item: GroceryItem
    
    var body: some View {
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

struct SearchResultsDropdown: View {
    @EnvironmentObject var model: GroceriesModel
    
    var body: some View {
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
                    if item.id != model.searchResults.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .padding(.bottom, 0)
        }
    }
}

struct AddItemSection: View {
    @EnvironmentObject var model: GroceriesModel
    
    var body: some View {
        VStack(spacing: 2) {
            // Category picker
            HStack {
                Text("Category:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Category", selection: $model.selectedCategory) {
                    ForEach(model.categories, id: \.self) { category in
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
