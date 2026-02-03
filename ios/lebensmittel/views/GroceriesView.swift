//
//  GroceriesView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct GroceriesView: View {
	@Environment(GroceriesModel.self) var model
	@Environment(\.colorScheme) var colorScheme
	@State private var hasGroups: Bool = true

	var body: some View {
		NavigationStack {
			VStack {
				if model.isLoading {
					ProgressView("Loading groceries...").background(Color(.systemBackground))
				} else if let errorMessage = model.errorMessage {
					Text("Error: \(errorMessage)").foregroundStyle(.red).background(Color(.systemBackground))
				} else {
					if !hasGroups {
						Text("Please create or join a group to start adding groceries.")
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.background(Color(.systemBackground))
					} else {
						HStack(spacing: 0) {
                        	if model.groceryItems.isEmpty {
                            	Text("No groceries yet. Add one below to get started!")
                                	.foregroundStyle(.secondary)
                                	.background(Color(.systemBackground))
                                	.frame(maxWidth: .infinity, maxHeight: .infinity)
                        	} else {
                            	EssentialsPane()
                            	Divider()
                                	.frame(width: 1)
                                	.background(Color(.separator))
                                	.padding(.vertical)
                            	CategoriesListPane()
                        	}
						}
						.padding(.horizontal, 12)
						.padding(.bottom, 6)
						.background(
							colorScheme == .dark
								? Color(.secondarySystemBackground) : Color(.systemBackground)
						)
						.clipShape(.rect(cornerRadius: 12))
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
			}
			.background(
				colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground)
			)
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Groceries")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					AuthMenuView()
				}
			}
			.task {
				do {
					let groups = try await AuthManager.shared.getUserGroups()
					hasGroups = !groups.isEmpty
				} catch {
					print("Error checking groups: \(error)")
				}
			}
			.onAppear {
				model.expandedCategories = Set(model.sortedCategories)
			}
		}
	}
}

struct EssentialsPane: View {
	@Environment(GroceriesModel.self) var model
	@Environment(\.colorScheme) var colorScheme

	var body: some View {
		List {
			Section(
				header:
					Text("Essentials")
					.font(.headline)
					.foregroundStyle(.primary)
					.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 12))
			) {
				if !model.essentialsItems.isEmpty {
					ForEach(
						model.essentialsItems.sorted {
							$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
						}
					) { item in
						GroceryItemRow(item: item)
							.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
							.listRowSeparator(.hidden)
							.listRowSpacing(0)
							.listRowBackground(
								colorScheme == .dark
									? Color(.secondarySystemBackground) : Color(.systemBackground)
							)
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								Button(role: .destructive) {
									model.deleteGroceryItem(item: item)
								} label: {
									Image(systemName: "trash")
										.imageScale(.small)
								}
							}
					}
				} else {
					Text("No Essentials")
						.foregroundStyle(.secondary)
						.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 12))
						.listRowSeparator(.hidden)
						.listRowBackground(
							colorScheme == .dark
								? Color(.secondarySystemBackground) : Color(.systemBackground))
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
		.background(
			colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
	}
}

struct CategoriesListPane: View {
	@Environment(GroceriesModel.self) var model
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
		.background(
			colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground))
	}
}

struct CategoryListSection: View {
	@Environment(GroceriesModel.self) var model
	@Environment(\.colorScheme) var colorScheme
	let category: String

	var body: some View {
		Section(
			header:
				Button {
					if model.expandedCategories.contains(category) {
						model.expandedCategories.remove(category)
					} else {
						model.expandedCategories.insert(category)
					}
				} label: {
					HStack {
						Text(category)
							.font(.headline)
							.foregroundStyle(.primary)
						Spacer()
						Image(
							systemName: model.expandedCategories.contains(category)
								? "chevron.down" : "chevron.right"
						)
						.font(.caption)
						.foregroundStyle(.secondary)
					}
				}
				.buttonStyle(PlainButtonStyle())
				.listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
		) {
			if model.expandedCategories.contains(category),
				let items = model.itemsByCategory[category], !items.isEmpty
			{
				ForEach(
					items.sorted {
						$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
					}
				) { item in
					GroceryItemRow(item: item)
						.listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
						.listRowSeparator(.hidden)
						.listRowSpacing(0)
						.listRowBackground(
							colorScheme == .dark
								? Color(.secondarySystemBackground) : Color(.systemBackground)
						)
						.swipeActions(edge: .trailing, allowsFullSwipe: true) {
							Button(role: .destructive) {
								model.deleteGroceryItem(item: item)
							} label: {
								Image(systemName: "trash")
									.imageScale(.small)
							}
						}
				}
			}
		}
	}
}

struct GroceryItemRow: View {
	@Environment(GroceriesModel.self) var model
	let item: GroceryItem

	var body: some View {
		HStack {
			Button {
				model.updateGroceryItem(item: item, field: .isNeeded(!item.isNeeded))
			} label: {
				Label(
					item.isNeeded ? "Mark as not needed" : "Mark as needed",
					systemImage: item.isNeeded ? "checkmark.square" : "square"
				)
				.labelStyle(.iconOnly)
				.foregroundStyle(item.isNeeded ? Color.green : Color.primary)
			}
			.buttonStyle(PlainButtonStyle())
			Text(item.name)
				.foregroundStyle(item.isNeeded ? Color.green : Color.primary)
			Spacer()
		}
		.padding(.vertical, 2)
	}
}

struct SearchResultsDropdown: View {
	@Environment(GroceriesModel.self) var model

	var body: some View {
		if model.isSearching && !model.searchResults.isEmpty {
			VStack(spacing: 0) {
				ForEach(model.searchResults.prefix(5)) { item in
					Button {
						model.selectExistingItem(item)
					} label: {
						HStack {
							Image(systemName: item.isNeeded ? "checkmark.square.fill" : "square")
								.foregroundStyle(item.isNeeded ? .green : .gray)
							VStack(alignment: .leading) {
								Text(item.name)
									.foregroundStyle(.primary)
								Text(item.category)
									.font(.caption)
									.foregroundStyle(.secondary)
							}
							Spacer()
							if !item.isNeeded {
								Text("Add to list")
									.font(.caption)
									.foregroundStyle(.blue)
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
	@Environment(GroceriesModel.self) var model

	var body: some View {
		VStack(spacing: 2) {
			// Category picker
			HStack {
				Text("Category:")
					.font(.caption)
					.foregroundStyle(.secondary)
				Picker(
					"Category",
					selection: Binding(
						get: { model.selectedCategory },
						set: { model.selectedCategory = $0 }
					)
				) {
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
				TextField(
					"Search or add new item",
					text: Binding(
						get: { model.newItemName },
						set: { model.newItemName = $0 }
					)
				)
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
