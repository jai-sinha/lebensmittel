//
//  ReceiptsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/20/25.
//

import SwiftUI

struct ReceiptsView: View {
    @EnvironmentObject var model: ReceiptsModel
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
                if model.isLoading {
                    ProgressView("Loading receipts...")
                } else if let errorMessage = model.errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red)
                } else {
                    List {
                        ForEach(model.groupReceiptsByMonthWithPersonTotals(), id: \ .month) { (month, receipts, jTotal, hTotal) in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedMonths.contains(month) },
                                    set: { expanded in
                                        if expanded {
                                            expandedMonths.insert(month)
                                        } else {
                                            expandedMonths.remove(month)
                                        }
                                    }
                                ),
                                content: {
                                    ForEach(receipts) { receipt in
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
                                                        ForEach(receipt.items, id: \ .self) { item in
                                                            Text("• \(item)")
                                                                .font(.body)
                                                        }
                                                    }
                                                    if !receipt.notes.trimmingCharacters(in: .whitespaces).isEmpty {
                                                        Text("Notes: \(receipt.notes)")
                                                            .font(.body)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                .padding(.top, 4)
                                            },
                                            label: {
                                                HStack {
                                                    Text(receipt.date)
                                                        .font(.headline)
                                                    Spacer()
                                                    Text(receipt.purchasedBy)
                                                        .font(.subheadline)
                                                        .foregroundColor(.blue)
                                                    Spacer()
                                                    Text(String(format: "€%.2f", receipt.totalAmount))
                                                        .font(.subheadline)
                                                        .foregroundColor(.green)
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
                                                editNotes = receipt.notes
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
                                    // Monthly person totals
                                    HStack {
                                        Text("Jai's Total: ")
                                            .font(.subheadline)
                                            .bold()
                                        Text(String(format: "€%.2f", jTotal))
                                            .font(.subheadline)
                                            .foregroundColor(.green)
                                            .bold()
                                        Spacer()
                                        Text("Hanna's Total: ")
                                            .font(.subheadline)
                                            .bold()
                                        Text(String(format: "€%.2f", hTotal))
                                            .font(.subheadline)
                                            .foregroundColor(.green)
                                            .bold()
                                    }
                                    .padding(.top, 8)
                                },
                                label: {
                                    Text(month)
                                        .font(.title3)
                                        .bold()
                                        .padding(.vertical, 4)
                                }
                            )
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Receipts")
            .onAppear {
                model.fetchReceipts()
                // Expand only the current month by default
                expandedMonths = [model.currentMonth]
            }
            // MARK: Edit Sheet
            .sheet(isPresented: $showEditSheet) {
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
                            .cornerRadius(8)
                    }
                    if !editError.isEmpty {
                        Text(editError)
                            .foregroundColor(.red)
                            .font(.callout)
                    }
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            showEditSheet = false
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
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
                                model.updateReceipt(receipt: receipt, price: price, purchasedBy: editPurchaser, notes: editNotes)
                            }
                            showEditSheet = false
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding(30)
                .presentationDetents([.medium])
            }
        }
    }
}
