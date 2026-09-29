//
//  ShoppingView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

/// Main shopping list view, including the checkout sheet.
struct ShoppingView: View {
	@Environment(ShoppingModel.self) var model
	@Environment(GroupModel.self) var groupModel
	// Checkout dialog state
	@State private var showCheckoutSheet = false

	var body: some View {
		NavigationStack {
			VStack {
				if !groupModel.hasActiveGroup {
					Text("Set a group ID from the top-right menu to see your shopping list.")
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.tintedBackground(.orange, dark: .blue)
				} else {
					if model.isLoading {
						ProgressView("Loading shopping list...")
					} else if let errorMessage = model.errorMessage {
						InlineErrorView(message: errorMessage)
							.refreshable {
								model.errorMessage = nil
								await model.fetchGroceries()
							}
					} else {
List {
						listContent
					}
					.scrollContentBackground(.hidden)
					.refreshable {
							model.errorMessage = nil
							await model.fetchGroceries()
						}
					}
					Spacer()
					// Checkout button
					Button {
						showCheckoutSheet = true
					} label: {
						Text("Checkout")
							.font(.headline)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 12)
					}
					.buttonStyle(.borderedProminent)
					.padding(.horizontal, 12)
					.padding(.top, 4)
					.padding(.bottom, 12)
					.clipShape(.rect(cornerRadius: 10))
				}
			}
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Shopping List")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					StatusIconView()
				}
				ToolbarItem(placement: .topBarTrailing) {
					GroupSheetView()
				}
			}

			// MARK: Checkout Sheet
			.sheet(isPresented: $showCheckoutSheet) {
				CheckoutSheetView(
					onCancel: { showCheckoutSheet = false },
					onSubmit: { price, purchaser, notes in
						model.createReceipt(price: price, purchasedBy: purchaser, notes: notes)
						showCheckoutSheet = false
					}
				)
			}
			.tintedBackground(.orange, dark: .blue, extendsSafeArea: true)
		}
	}

	@ViewBuilder
	private var listContent: some View {
		if !model.uncheckedItems.isEmpty {
			Section("To Buy") {
				ForEach(model.uncheckedItems) { item in
					ShoppingRow(
						item: item,
						toggleChecked: {
							model.updateGroceryItem(
								item: item,
								field: .isShoppingChecked(true)
							)
						},
						toggleNeeded: {
							Task { @MainActor in
								try? await Task.sleep(for: .milliseconds(350))
								model.updateGroceryItem(
									item: item,
									field: .isNeeded(false)
								)
							}
						}
					)
				}
			}
		}

		if !model.checkedItems.isEmpty {
			Section("Completed") {
				ForEach(model.checkedItems) { item in
					ShoppingRow(
						item: item,
						toggleChecked: {
							model.updateGroceryItem(
								item: item,
								field: .isShoppingChecked(false)
							)
						},
						toggleNeeded: {
							Task { @MainActor in
								try? await Task.sleep(for: .milliseconds(350))
								model.updateGroceryItem(
									item: item,
									field: .isNeeded(false)
								)
							}
						}
					)
				}
			}
		}

		if model.shoppingItems.isEmpty {
			Section {
				HStack {
					Spacer()
					VStack(spacing: 8) {
						Image(systemName: "cart")
							.imageScale(.large)
							.font(.largeTitle)
							.foregroundStyle(.gray)
						Text("No items to buy!")
							.foregroundStyle(.gray)
						Text("Add items in the Groceries tab")
							.font(.caption)
							.foregroundStyle(.gray)
					}
					Spacer()
				}
				.padding(.vertical, 40)
			}
		}
	}
}

/// A single row in the shopping list
struct ShoppingRow: View {
	let item: GroceryItem
	let toggleChecked: () -> Void
	let toggleNeeded: () -> Void

	var body: some View {
		HStack {
			Button(action: toggleChecked) {
				Label(
					item.isShoppingChecked ? "Mark as not yet in basket" : "Mark as in basket",
					systemImage: item.isShoppingChecked ? "checkmark.circle.fill" : "circle"
				)
				.labelStyle(.iconOnly)
				.foregroundStyle(item.isShoppingChecked ? .green : .gray)
			}
			.buttonStyle(PlainButtonStyle())

			Text(item.name)
				.strikethrough(item.isShoppingChecked)
				.foregroundStyle(item.isShoppingChecked ? .gray : .primary)

			Spacer()
		}
		.padding(.vertical, 2)
		.swipeActions(edge: .trailing) {
			Button(role: .destructive) {
				toggleNeeded()
			} label: {
				Label("Remove from list", systemImage: "trash")
			}
		}
	}
}

struct CheckoutSheetView: View {
	var onCancel: () -> Void

	var onSubmit: (_ price: Double, _ purchaser: String, _ notes: String) -> Void

	@State private var cost: String = ""
	@State private var purchaser: String = ""
	@State private var notes: String = ""
	@State private var error: String = ""

	private let groupModel: GroupModel = .shared

	var purchaserOptions: [String] {
		groupModel.activeGroup!.members
	}

	var body: some View {
		ReceiptFormSheet(
			title: "Submit Receipt",
			cost: $cost,
			purchaser: $purchaser,
			notes: $notes,
			error: $error,
			purchaserOptions: purchaserOptions,
			onCancel: onCancel,
			onSubmit: onSubmit
		)
	}
}
