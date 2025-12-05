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

	var body: some View {
		NavigationStack {
			VStack {
				if let errorMessage = model.errorMessage {
					Text("Error: \(errorMessage)").foregroundStyle(.red)
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
				}
			}
			.navigationBarTitleDisplayMode(.inline)
			.navigationTitle("Receipts")
			.onAppear {
				//                model.fetchReceipts()
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
				HStack {
					Text("Jai's Total:")
						.font(.subheadline)
						.bold()
					Text(String(format: "€%.2f", group.jaiTotal))
						.font(.subheadline)
						.foregroundStyle(.green)
						.bold()
					Spacer()
					Text("Hanna's Total:")
						.font(.subheadline)
						.bold()
					Text(String(format: "€%.2f", group.hannaTotal))
						.font(.subheadline)
						.foregroundStyle(.green)
						.bold()
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
					Text(String(format: "€%.2f", receipt.totalAmount))
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

	var body: some View {
		VStack(spacing: 25) {
			Text("Edit Receipt")
				.font(.title)
				.fontWeight(.semibold)
			VStack(alignment: .leading, spacing: 12) {
				Text("Total Cost (€)")
					.font(.headline)
				TextField("", text: $editCost)
					.keyboardType(.decimalPad)
					.textFieldStyle(RoundedBorderTextFieldStyle())
					.font(.body)
			}
			VStack(alignment: .leading, spacing: 12) {
				Text("Purchased by")
					.font(.headline)
				Picker("Purchased by", selection: $editPurchaser) {
					Text("Jai").tag("Jai")
					Text("Hanna").tag("Hanna")
				}
				.pickerStyle(SegmentedPickerStyle())
			}
			VStack(alignment: .leading, spacing: 12) {
				Text("Notes (optional)")
					.font(.headline)
				TextEditor(text: $editNotes)
					.frame(minHeight: 40, maxHeight: 120)
					.font(.body)
					.background(Color(.systemGray6))
					.clipShape(.rect(cornerRadius: 8))
			}
			if !editError.isEmpty {
				Text(editError)
					.foregroundStyle(.red)
					.font(.callout)
			}
			HStack(spacing: 20) {
				Button("Cancel") {
					showEditSheet = false
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 10)
				.background(Color.red.opacity(0.8))
				.foregroundStyle(.white)
				.clipShape(.rect(cornerRadius: 8))
				Spacer()
				Button("Submit") {
					guard let price = Double(editCost), price > 0 else {
						editError = "Please enter a valid cost."
						return
					}
					guard !editPurchaser.trimmingCharacters(in: .whitespaces).isEmpty else {
						editError = "Please select who purchased."
						return
					}
					if let receipt = selectedReceipt {
						model.updateReceipt(
							receipt: receipt, price: price, purchasedBy: editPurchaser,
							notes: editNotes)
					}
					showEditSheet = false
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
}
