//
//  GroceriesView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct GroceriesView: View {
	@Environment(GroceriesModel.self) var model
	@Environment(GroupModel.self) var groupModel
	@Environment(\.colorScheme) var colorScheme
	@State private var isAddItemSheetPresented = false

	var body: some View {
		NavigationStack {
			VStack {
				if model.isLoading {
					ProgressView("Loading groceries...").background(Color(.systemBackground))
				} else if let errorMessage = model.errorMessage {
					InlineErrorView(message: errorMessage)
						.refreshable {
							model.errorMessage = nil
							model.fetchGroceries()
						}
				} else {
					if !groupModel.hasActiveGroup {
						Text("Set a group ID from the top-right menu to start adding groceries.")
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
								.refreshable {
									model.fetchGroceries()
								}
						}
						.background(
							colorScheme == .dark
								? Color(.secondarySystemBackground) : Color(.systemBackground)
						)
						.clipShape(.rect(cornerRadius: 12))
						.shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
						.padding(.horizontal, 12)

						Button {
							isAddItemSheetPresented = true
						} label: {
							Text("Add or search items")
								.font(.headline)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 12)
						}
						.buttonStyle(.borderedProminent)
						.padding(.horizontal, 12)
						.padding(.top, 4)
						.padding(.bottom, 12)
						.clipShape(.rect(cornerRadius: 10))
						.sheet(isPresented: $isAddItemSheetPresented) {
							AddItemSheet()
						}
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
					GroupSheetView()
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
		.scrollDismissesKeyboard(.interactively)
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
		.onLongPressGesture(
			minimumDuration: 0.25,
			perform: {
				let generator = UIImpactFeedbackGenerator(style: .heavy)
				generator.impactOccurred()
				isPressed = false
				showDeleteConfirmation = true
			},
			onPressingChanged: { pressing in
				isPressed = pressing
				if pressing {
					let generator = UIImpactFeedbackGenerator(style: .light)
					generator.prepare()
					generator.impactOccurred()
				}
			}
		)
		.confirmationDialog(
			"Delete \"\(item.name)\"?", isPresented: $showDeleteConfirmation,
			titleVisibility: .visible
		) {
			Button("Delete", role: .destructive) {
				model.deleteGroceryItem(item: item)
			}
			Button("Cancel", role: .cancel) {}
		}
	}
}

// MARK: - Add Item Sheet

struct AddItemSheet: View {
	@Environment(GroceriesModel.self) var model
	@Environment(\.dismiss) var dismiss
	@Environment(\.colorScheme) var colorScheme
	@FocusState private var isAddItemFieldFocused: Bool

	private var displayedResults: ArraySlice<GroceryItem> {
		model.searchResults.prefix(5)
	}

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 16) {
				HStack(spacing: 4) {
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

				HStack {
					TextField(
						"Search or add new item",
						text: Binding(
							get: { model.newItemName },
							set: { model.newItemName = $0 }
						)
					)
					.focused($isAddItemFieldFocused)
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.onSubmit {
						submitItem()
					}

					Button(model.exactMatch != nil ? "Select" : "Add") {
						submitItem()
					}
					.disabled(model.newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}

				ZStack(alignment: .top) {
					Color.clear.frame(height: 260)

					if model.isSearching && !displayedResults.isEmpty {
						VStack(alignment: .leading, spacing: 0) {
							Text("Matches")
								.font(.caption)
								.foregroundStyle(.secondary)
								.padding(.horizontal, 16)
								.padding(.top, 14)
								.padding(.bottom, 8)

							ForEach(Array(displayedResults.enumerated()), id: \.element.id) { index, item in
								Button {
									model.selectExistingItem(item)
									dismiss()
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
										Text(item.isNeeded ? "Remove from list" : "Add to list")
											.font(.caption)
											.foregroundStyle(.blue)
									}
									.padding(.horizontal, 16)
									.padding(.vertical, 10)
								}
								.buttonStyle(PlainButtonStyle())

								if index < displayedResults.count - 1 {
									Divider()
										.padding(.leading, 16)
								}
							}
						}
						.background(
							RoundedRectangle(cornerRadius: 16)
								.fill(
									colorScheme == .dark
										? Color(.tertiarySystemBackground)
										: Color(.secondarySystemBackground)
								)
						)
						.overlay(
							RoundedRectangle(cornerRadius: 16)
								.stroke(Color(.separator).opacity(0.25), lineWidth: 1)
						)
					}
				}

				Spacer(minLength: 0)
			}
			.padding(.horizontal, 16)
			.padding(.top, 16)
			.navigationTitle("Add Item")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.onAppear {
				isAddItemFieldFocused = true
			}
			.onDisappear {
				model.newItemName = ""
			}
		}
		.presentationDetents([.large])
		.presentationDragIndicator(.visible)
	}

	private func submitItem() {
		model.addItem()
		dismiss()
	}
}
