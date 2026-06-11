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
	@Environment(\.colorScheme) var colorScheme
	// Checkout dialog state
	@State private var showCheckoutSheet = false

	var body: some View {
		NavigationStack {
			VStack {
				if !groupModel.hasActiveGroup {
					Text("Set a group ID from the top-right menu to see your shopping list.")
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background(Color(.systemBackground))
				} else {
					if model.isLoading {
						ProgressView("Loading shopping list...")
					} else if let errorMessage = model.errorMessage {
						InlineErrorView(message: errorMessage)
							.refreshable {
								model.errorMessage = nil
								model.fetchGroceries()
							}
					} else {
						List {
							listContent
						}
						.refreshable {
							model.errorMessage = nil
							model.fetchGroceries()
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
			.background(
				colorScheme == .dark ? Color(.systemBackground) : Color(.secondarySystemBackground)
			)
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Shopping List")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					GroupIDMenuView()
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

		}
	}

	@ViewBuilder
	private var listContent: some View {
		if !model.uncheckedItems.isEmpty {
			Section("To Buy") {
				ForEach(model.uncheckedItems) { item in
					ShoppingRow(item: item) {
						model.updateGroceryItem(
							item: item,
							field: GroceriesModel.GroceryItemField.isShoppingChecked(true)
						)
					}
				}
			}
		}

		if !model.checkedItems.isEmpty {
			Section("Completed") {
				ForEach(model.checkedItems) { item in
					ShoppingRow(item: item) {
						model.updateGroceryItem(
							item: item,
							field: GroceriesModel.GroceryItemField.isShoppingChecked(false)
						)
					}
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
	let action: () -> Void

	var body: some View {
		HStack {
			Button(action: action) {
				Label(
					item.isShoppingChecked ? "Mark as not purchased" : "Mark as purchased",
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
	}
}

struct CheckoutSheetView: View {
	var onCancel: () -> Void

	var onSubmit: (_ price: Double, _ purchaser: String, _ notes: String) -> Void

	@State private var cost: String = ""
	@State private var purchaser: String = ""
	@State private var notes: String = ""
	@State private var error: String = ""

	var body: some View {
		VStack(spacing: 25) {
			Text("Submit Receipt")
				.font(.title)
				.bold()

			VStack(alignment: .leading, spacing: 12) {
				Text("Total Cost (€)")
					.font(.headline)
				TextField("", text: $cost)
					.keyboardType(.decimalPad)
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.font(.body)
			}

			VStack(alignment: .leading, spacing: 12) {
				Text("Purchased by")
					.font(.headline)
				TextField("Purchased by", text: $purchaser)
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.font(.body)
			}

			VStack(alignment: .leading, spacing: 12) {
				Text("Notes (optional)")
					.font(.headline)
				TextEditor(text: $notes)
					.frame(minHeight: 40, maxHeight: 120)
					.font(.body)
					.background(Color(.systemGray6))
					.clipShape(.rect(cornerRadius: 8))
			}

			if !error.isEmpty {
				Text(error)
					.foregroundStyle(.red)
					.font(.callout)
			}

			HStack(spacing: 20) {
				Button("Cancel") {
					onCancel()
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 10)
				.background(Color.red.opacity(0.8))
				.foregroundStyle(.white)
				.clipShape(.rect(cornerRadius: 8))

				Spacer()

				Button("Submit") {
					submit()
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 10)
				.background(Color.blue)
				.foregroundStyle(.white)
				.clipShape(.rect(cornerRadius: 8))
			}
		}
		.padding(30)
		.presentationDetents([.medium])
	}

	private func submit() {
		// accept both "." and "," as decimal separators for euro/us standards
		let normalized = cost.replacingOccurrences(of: ",", with: ".")
		guard let price = Double(normalized), price >= 0 else {
			error = "Please enter a valid cost."
			return
		}
		guard !purchaser.trimmingCharacters(in: .whitespaces).isEmpty else {
			error = "Please enter who purchased."
			return
		}
		onSubmit(price, purchaser, notes)
	}
}

#Preview {
	ShoppingView()
}
