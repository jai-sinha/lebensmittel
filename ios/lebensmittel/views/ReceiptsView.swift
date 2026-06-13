//
//  ReceiptsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/20/25.
//

import SwiftUI

struct ReceiptsView: View {
	@Environment(ReceiptsModel.self) var model
	@State private var expandedReceiptIDs: Set<String> = []
	@State private var expandedMonths: Set<String> = []
	// Edit sheet state
	@State private var showEditSheet = false
	@State private var selectedReceipt: Receipt? = nil
	@State private var editCost: String = ""
	@State private var editPurchaser: String = ""
	@State private var editNotes: String = ""
	@State private var editError: String = ""

	@Environment(GroupModel.self) var groupModel

	var body: some View {
		NavigationStack {
			VStack {
				if let errorMessage = model.errorMessage {
					InlineErrorView(message: errorMessage)
						.refreshable {
							model.errorMessage = nil
							model.fetchReceipts()
						}
				} else if !groupModel.hasActiveGroup {
					Text("Set a group ID from the top-right menu to start tracking receipts.")
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background(Color(.systemBackground))
				} else if model.receipts.isEmpty {
					Text("No receipts yet. Create one from the Shopping tab to get started!")
						.foregroundStyle(.secondary)
				} else {
					List {
						ForEach(model.groupReceiptsByMonthWithPersonTotals()) { group in
							MonthGroup(
								group: group,
								expandedMonths: $expandedMonths,
								expandedReceiptIDs: $expandedReceiptIDs,
								showEditSheet: $showEditSheet,
								selectedReceipt: $selectedReceipt,
								editCost: $editCost,
								editPurchaser: $editPurchaser,
								editNotes: $editNotes,
								editError: $editError
							)
						}
					}
					.refreshable {
						model.errorMessage = nil
						model.fetchReceipts()
					}
				}
			}
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Receipts")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					GroupSheetView()
				}
			}
			.onAppear {
				// Expand only the current month by default
				expandedMonths = [model.currentMonth]
			}
			.sheet(isPresented: $showEditSheet) {
				EditReceiptSheet(
					selectedReceipt: $selectedReceipt,
					editCost: $editCost,
					editPurchaser: $editPurchaser,
					editNotes: $editNotes,
					editError: $editError,
					showEditSheet: $showEditSheet
				)
			}
		}
	}
}

struct MonthGroup: View {
	let group: MonthlyReceiptsGroup
	@Binding var expandedMonths: Set<String>
	@Binding var expandedReceiptIDs: Set<String>
	@Binding var showEditSheet: Bool
	@Binding var selectedReceipt: Receipt?
	@Binding var editCost: String
	@Binding var editPurchaser: String
	@Binding var editNotes: String
	@Binding var editError: String

	@Environment(ReceiptsModel.self) var model

	var body: some View {
		DisclosureGroup(
			isExpanded: Binding(
				get: { expandedMonths.contains(group.month) },
				set: { expanded in
					if expanded {
						expandedMonths.insert(group.month)
					} else {
						expandedMonths.remove(group.month)
					}
				}
			),
			content: {
				ForEach(group.receipts) { receipt in
					ReceiptRow(
						receipt: receipt,
						expandedReceiptIDs: $expandedReceiptIDs,
						showEditSheet: $showEditSheet,
						selectedReceipt: $selectedReceipt,
						editCost: $editCost,
						editPurchaser: $editPurchaser,
						editNotes: $editNotes,
						editError: $editError
					)
				}
				// Monthly person totals
				VStack(alignment: .leading) {
					ForEach(group.userTotals.keys.sorted(), id: \.self) { purchaser in
						HStack {
							Text("\(purchaser)'s Total:")
								.font(.subheadline)
								.bold()
							Text(
								group.userTotals[purchaser] ?? 0.0,
								format: .currency(code: "EUR").precision(.fractionLength(2))
							)
							.font(.subheadline)
							.foregroundStyle(.green)
							.bold()
						}
					}
				}
				.padding(.leading, -20)
			},
			label: {
				Text(group.month)
					.font(.title3)
					.bold()
					.padding(.vertical, 4)
			}
		)
	}
}

struct ReceiptRow: View {
	let receipt: Receipt
	@Binding var expandedReceiptIDs: Set<String>
	@Binding var showEditSheet: Bool
	@Binding var selectedReceipt: Receipt?
	@Binding var editCost: String
	@Binding var editPurchaser: String
	@Binding var editNotes: String
	@Binding var editError: String

	@Environment(ReceiptsModel.self) var model

	var body: some View {
		DisclosureGroup(
			isExpanded: Binding(
				get: { expandedReceiptIDs.contains(receipt.id) },
				set: { expanded in
					if expanded {
						expandedReceiptIDs.insert(receipt.id)
					} else {
						expandedReceiptIDs.remove(receipt.id)
					}
				}
			),
			content: {
				VStack(alignment: .leading, spacing: 8) {
					if !receipt.items.isEmpty {
						Text("Items:")
							.font(.subheadline)
							.bold()
						ForEach(receipt.items, id: \.self) { item in
							Text("• \(item)")
								.font(.body)
						}
					} else {
						Text("No items listed.")
							.font(.body)
							.foregroundStyle(.secondary)
					}
					if let notes = receipt.notes,
						!notes.trimmingCharacters(in: .whitespaces).isEmpty
					{
						Text("Notes: \(notes)")
							.font(.body)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.top, 4)
			},
			label: {
				HStack {
					Text(receipt.date.dropFirst(5))
						.font(.headline)
					Spacer()
					Text(receipt.purchasedBy)
						.font(.subheadline)
						.foregroundStyle(.blue)
					Spacer()
					Text(
						receipt.totalAmount,
						format: .currency(code: "EUR").precision(.fractionLength(2))
					)
					.font(.subheadline)
					.foregroundStyle(.green)
				}
			}
		)
		// Swipe actions for edit/delete
		.swipeActions(edge: .trailing) {
			Button {
				// Prefill fields and show sheet
				selectedReceipt = receipt
				editCost = String(format: "%.2f", receipt.totalAmount)
				editPurchaser = receipt.purchasedBy
				editNotes = receipt.notes ?? ""
				editError = ""
				showEditSheet = true
			} label: {
				Label("Edit", systemImage: "pencil")
			}.tint(.blue)
			Button(role: .destructive) {
				model.deleteReceipt(receiptId: receipt.id)
			} label: {
				Label("Delete", systemImage: "trash")
			}
		}
	}
}

struct EditReceiptSheet: View {
	@Binding var selectedReceipt: Receipt?
	@Binding var editCost: String
	@Binding var editPurchaser: String
	@Binding var editNotes: String
	@Binding var editError: String
	@Binding var showEditSheet: Bool

	@Environment(ReceiptsModel.self) var model
	private let groupModel: GroupModel = .shared

	var purchaserOptions: [String] {
		groupModel.activeGroup!.members
	}

	var body: some View {
		ReceiptFormSheet(
			title: "Edit Receipt",
			cost: $editCost,
			purchaser: $editPurchaser,
			notes: $editNotes,
			error: $editError,
			purchaserOptions: purchaserOptions,
			onCancel: { showEditSheet = false },
			onSubmit: { price, purchaser, notes in
				if let receipt = selectedReceipt {
					model.updateReceipt(
						receipt: receipt, price: price, purchasedBy: purchaser,
						notes: notes)
				}
				showEditSheet = false
			}
		)
	}
}
