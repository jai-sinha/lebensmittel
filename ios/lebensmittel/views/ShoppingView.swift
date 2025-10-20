//
//  ShoppingView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ShoppingView: View {
    @StateObject private var model = ShoppingModel()
    // Checkout dialog state
    @State private var showCheckoutSheet = false
    @State private var checkoutCost = ""
    @State private var checkoutPurchaser = ""
    @State private var checkoutNotes = ""
    @State private var checkoutError = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                if model.isLoading {
                    ProgressView("Loading shopping list...")
                } else if let errorMessage = model.errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red)
                } else {
                    List {
                        if !model.uncheckedItems.isEmpty {
                            Section("To Buy") {
                                ForEach(model.uncheckedItems) { item in
                                    HStack {
                                        Button(action: {
                                            model.updateShoppingChecked(item: item, isChecked: !item.isShoppingChecked)
                                        }) {
                                            Image(systemName: "circle")
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        Text(item.name)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        
                        if !model.checkedItems.isEmpty {
                            Section("Completed") {
                                ForEach(model.checkedItems) { item in
                                    HStack {
                                        Button(action: {
                                            model.updateShoppingChecked(item: item, isChecked: !item.isShoppingChecked)
                                        }) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        Text(item.name)
                                            .strikethrough()
                                            .foregroundColor(.gray)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        
                        if model.shoppingItems.isEmpty {
                            Section {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "cart")
                                            .font(.system(size: 40))
                                            .foregroundColor(.gray)
                                        Text("No items to buy!")
                                            .foregroundColor(.gray)
                                        Text("Add items in the Groceries tab")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 40)
                            }
                        }
                    }
                }
                Spacer()
                // Checkout button
                if !model.uncheckedItems.isEmpty {
                    Button(action: {
                        showCheckoutSheet = true
                        checkoutCost = ""
                        checkoutPurchaser = ""
                        checkoutNotes = ""
                        checkoutError = ""
                    }) {
                        Text("Checkout")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding([.horizontal, .bottom])
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Shopping List")
            .onAppear {
                model.fetchShoppingItems()
            }
            .sheet(isPresented: $showCheckoutSheet) {
                VStack(spacing: 20) {
                    Text("Checkout Receipt")
                        .font(.headline)
                    TextField("Cost", text: $checkoutCost)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Who purchased?", text: $checkoutPurchaser)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Notes (optional)", text: $checkoutNotes)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    if !checkoutError.isEmpty {
                        Text(checkoutError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    HStack {
                        Button("Cancel") {
                            showCheckoutSheet = false
                        }
                        Spacer()
                        Button("Submit") {
                            // Validate cost and purchaser
                            guard let price = Double(checkoutCost), price > 0 else {
                                checkoutError = "Please enter a valid cost."
                                return
                            }
                            guard !checkoutPurchaser.trimmingCharacters(in: .whitespaces).isEmpty else {
                                checkoutError = "Please enter who purchased."
                                return
                            }
                            model.createReceipt(price: price, purchasedBy: checkoutPurchaser, notes: checkoutNotes)
                            showCheckoutSheet = false
                        }
                    }
                }
                .padding()
            }
        }
    }
}

#Preview {
    ShoppingView()
}
