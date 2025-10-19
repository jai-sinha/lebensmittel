//
//  ShoppingView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ShoppingView: View {
    @StateObject private var model = ShoppingModel()
    
    var neededItems: [GroceryItem] {
        return model.shoppingItems
    }
    
    var uncheckedItems: [GroceryItem] {
        return neededItems.filter { !$0.isShoppingChecked }
    }
    
    var checkedItems: [GroceryItem] {
        return neededItems.filter { $0.isShoppingChecked }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if model.isLoading {
                    ProgressView("Loading shopping list...")
                } else if let errorMessage = model.errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red)
                } else {
                    List {
                        if !uncheckedItems.isEmpty {
                            Section("To Buy") {
                                ForEach(uncheckedItems) { item in
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
                        
                        if !checkedItems.isEmpty {
                            Section("Completed") {
                                ForEach(checkedItems) { item in
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
                        
                        if neededItems.isEmpty {
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
