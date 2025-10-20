//
//  ReceiptsView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/20/25.
//

import SwiftUI

struct ReceiptsView: View {
    @StateObject private var model = ReceiptsModel()
    @State private var expandedReceiptIDs: Set<String> = []
    @State private var expandedMonths: Set<String> = []
    
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
        }
    }
}
