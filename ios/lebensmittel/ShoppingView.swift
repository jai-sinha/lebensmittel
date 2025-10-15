//
//  ShoppingView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

struct ShoppingView: View {
    @ObservedObject var appData: AppData
    
    var neededItems: [GroceryItem] {
        return appData.groceryItems.filter { $0.isNeeded }
    }
    
    var uncheckedItems: [GroceryItem] {
        return neededItems.filter { !$0.isShoppingChecked }
    }
    
    var checkedItems: [GroceryItem] {
        return neededItems.filter { $0.isShoppingChecked }
    }
    
    var body: some View {
        NavigationView {
            List {
                if !uncheckedItems.isEmpty {
                    Section("To Buy") {
                        ForEach(uncheckedItems) { item in
                            HStack {
                                Button(action: {
                                    appData.toggleShoppingItemChecked(item: item)
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
                                    appData.toggleShoppingItemChecked(item: item)
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
            .navigationTitle("Shopping List")
        }
    }
}

#Preview {
    ShoppingView(appData: AppData())
}
