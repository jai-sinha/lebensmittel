//
//  GroceriesView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct GroceriesView: View {
	@Environment(GroceriesModel.self) var model
	@Environment(AuthStateManager.self) var authManager
	@Environment(\.colorScheme) var colorScheme

	var body: some View {
		NavigationStack {
			VStack {
				if model.isLoading {
					ProgressView("Loading groceries...").background(Color(.systemBackground))
				} else if let errorMessage = model.errorMessage {
					ScrollView {
						VStack(spacing: 12) {
							Text("Error: \(errorMessage)")
								.foregroundStyle(.red)
							Text("Pull down to retry")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity)
						.padding(.top, 100)
					}
					.refreshable {
						model.fetchGroceries()
					}
					.background(Color(.systemBackground))
				} else {
					if !authManager.isAuthenticated {
						GuestSignInPrompt(message: "Sign in and join a household group to manage your shared grocery list.")
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.background(Color(.systemBackground))
					} else if authManager.currentUserGroups.isEmpty {
						Text("Please create or join a group to start adding groceries.")
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity, maxHeight: .infinity)
							.background(Color(.systemBackground))
					} else {
						VStack(spacing: 0) {
							// Sticky category pills row
							ScrollView(.horizontal, showsIndicators: false) {
								HStack(spacing: 8) {
									ForEach(model.categories, id: \.self) { category in
										CategoryPill(category: category)
									}
								}
								.padding(.horizontal, 16)
								.padding(.vertical, 10)
							}
							.mask(
								LinearGradient(
									stops: [
										.init(color: .clear, location: 0),
										.init(color: .black, location: 0.06),
										.init(color: .black, location: 0.94),
										.init(color: .clear, location: 1),
									],
									startPoint: .leading,
									endPoint: .trailing
								)
							)

							Divider()

							// 2-col item grid
							GroceriesGridView()
						}
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
			.onAppear {
				model.expandedCategories = Set(model.sortedCategories)
			}
		}
	}
}

// MARK: - Category Pills

struct CategoryPill: View {
	@Environment(GroceriesModel.self) var model
	let category: String

	private var isSelected: Bool { model.selectedCategory == category }

	var body: some View {
		Button {
			model.selectedCategory = category
		} label: {
			Text(category)
				.font(.subheadline)
				.fontWeight(isSelected ? .semibold : .regular)
				.padding(.horizontal, 16)
				.padding(.vertical, 8)
				.background(
					Capsule()
						.fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
				)
				.foregroundStyle(isSelected ? .white : .primary)
		}
		.buttonStyle(PlainButtonStyle())
		.animation(.easeInOut(duration: 0.15), value: isSelected)
	}
}

// MARK: - Items Grid

struct GroceriesGridView: View {
	@Environment(GroceriesModel.self) var model

	private let columns = [
		GridItem(.flexible(), spacing: 12),
		GridItem(.flexible(), spacing: 12),
	]

	private var items: [GroceryItem] {
		(model.itemsByCategory[model.selectedCategory] ?? [])
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	var body: some View {
		ScrollView {
			if items.isEmpty {
				VStack(spacing: 10) {
					Image(systemName: "cart")
						.font(.system(size: 36))
						.foregroundStyle(.quaternary)
					Text("No items in \(model.selectedCategory)")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity)
				.padding(.top, 60)
			} else {
				LazyVGrid(columns: columns, spacing: 12) {
					ForEach(items) { item in
						GroceryItemCard(item: item)
					}
				}
				.padding(12)
			}
		}
		// Reset scroll position when the category changes
		.id(model.selectedCategory)
	}
}

// MARK: - Item Card

struct GroceryItemCard: View {
	@Environment(GroceriesModel.self) var model
	@Environment(\.colorScheme) var colorScheme
	let item: GroceryItem

	@State private var showDeleteConfirmation = false
	@State private var isPressed = false

	var body: some View {
		HStack(spacing: 8) {
			Text(item.name)
				.font(.subheadline)
				.fontWeight(.medium)
				.foregroundStyle(item.isNeeded ? .green : .primary)
				.lineLimit(2)
				.multilineTextAlignment(.leading)
				.frame(maxWidth: .infinity, alignment: .leading)
			Image(systemName: item.isNeeded ? "checkmark.circle.fill" : "circle")
				.font(.title3)
				.foregroundStyle(item.isNeeded ? .green : Color(.tertiaryLabel))
		}
		.padding(12)
		.frame(maxWidth: .infinity)
		.background(
			RoundedRectangle(cornerRadius: 12)
				.fill(
					colorScheme == .dark
						? Color(.tertiarySystemBackground)
						: Color(.systemBackground)
				)
		)
		.overlay(
			RoundedRectangle(cornerRadius: 12)
				.stroke(
					item.isNeeded
						? Color.green.opacity(0.35)
						: Color(.separator).opacity(0.4),
					lineWidth: 1
				)
		)
		.scaleEffect(isPressed ? 0.96 : 1.0)
		.animation(.easeInOut(duration: 0.15), value: isPressed)
		.contentShape(Rectangle())
		.onTapGesture {
			model.updateGroceryItem(item: item, field: .isNeeded(!item.isNeeded))
		}
		.onLongPressGesture(minimumDuration: 0.5, perform: {
			let generator = UIImpactFeedbackGenerator(style: .heavy)
			generator.impactOccurred()
			isPressed = false
			showDeleteConfirmation = true
		}, onPressingChanged: { pressing in
			isPressed = pressing
			if pressing {
				let generator = UIImpactFeedbackGenerator(style: .light)
				generator.prepare()
				generator.impactOccurred()
			}
		})
		.confirmationDialog("Delete \"\(item.name)\"?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
			Button("Delete", role: .destructive) {
				model.deleteGroceryItem(item: item)
			}
			Button("Cancel", role: .cancel) {}
		}
	}
}

// MARK: - Search Results Dropdown

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

// MARK: - Add Item Section (untouched)

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
						get: { model.searchCategory },
						set: { model.searchCategory = $0 }
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
