//
//  lebensmittelApp.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

@main
struct lebensmittelApp: App {
    @StateObject private var groceriesModel = GroceriesModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(groceriesModel)
                .onAppear {
                    SocketService.shared.start(with: groceriesModel)
                }
        }
    }
}
