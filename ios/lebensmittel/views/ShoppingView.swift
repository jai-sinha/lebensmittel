//
//  ShoppingView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ShoppingView: View {
    @StateObject private var model = ShoppingModel()
    
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Shopping List")
            .onAppear {
                model.fetchShoppingItems()
            }
        }
    }
}

#Preview {
    ShoppingView()
}
