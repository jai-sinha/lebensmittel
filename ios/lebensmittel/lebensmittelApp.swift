//
//  lebensmittelApp.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

@Observable
class AuthStateManager {
    var isAuthenticated = false
    var currentUser: User?
    var currentUserGroups: [AuthGroup] = []
    var currentUserActiveGroupId: String?
    var currentGroupUsers: [GroupUser] = []
    var isCheckingAuth = true
    var errorMessage: String?

    func checkAuthentication() {
        Task {
            do {
                let isAuth = try await AuthManager.shared.isAuthenticated()
                let user = try await AuthManager.shared.getCurrentUser()
                let userGroups = try await AuthManager.shared.getUserGroups()
                let userActiveGroupId = try await AuthManager.shared.getActiveGroupId()
                let groupUsers = try await AuthManager.shared.getUsersInGroup()

                await MainActor.run {
                    self.isAuthenticated = isAuth
                    self.currentUser = user
                    self.currentUserGroups = userGroups
                    self.currentUserActiveGroupId = userActiveGroupId
                    self.currentGroupUsers = groupUsers
                    self.isCheckingAuth = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAuthenticated = false
                    self.isCheckingAuth = false
                }
            }
        }
    }

    func logout() {
        Task {
            do {
                try await AuthManager.shared.logout()
                await MainActor.run {
                    self.isAuthenticated = false
                    self.currentUser = nil
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

@main
struct lebensmittelApp: App {
    @State private var authManager = AuthStateManager()
    @State private var groceriesModel: GroceriesModel
    @State private var mealsModel: MealsModel
    @State private var receiptsModel: ReceiptsModel
    @State private var shoppingModel: ShoppingModel

    // Initialize shoppingModel with groceriesModel reference
    init() {
        let groceries = GroceriesModel()
        _groceriesModel = State(initialValue: groceries)
        _mealsModel = State(initialValue: MealsModel())
        _receiptsModel = State(initialValue: ReceiptsModel())
        _shoppingModel = State(initialValue: ShoppingModel(groceriesModel: groceries))
        _authManager = State(initialValue: AuthStateManager())
    }

    private func refreshData() {
		groceriesModel.fetchGroceries()
		mealsModel.fetchMealPlans()
		receiptsModel.fetchReceipts()
	}

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isCheckingAuth {
                    ProgressView("Loading...")
                } else if authManager.isAuthenticated {
                    ContentView()
                        .environment(groceriesModel)
                        .environment(mealsModel)
                        .environment(receiptsModel)
                        .environment(shoppingModel)
                        .environment(authManager)
                        .onAppear {
                            SocketService.shared.start(
                                with: groceriesModel,
                                mealsModel: mealsModel,
                                receiptsModel: receiptsModel,
                                shoppingModel: shoppingModel
                            )
                            // Initial data fetch
                            groceriesModel.fetchGroceries()
                            mealsModel.fetchMealPlans()
                            receiptsModel.fetchReceipts()
                        }
                        // Refresh data when app comes to foreground or group changes
                        .onReceive(
                            NotificationCenter.default.publisher(
                                for: UIApplication.willEnterForegroundNotification)
                        ) { _ in
                            refreshData()
                        }
                        .onReceive(
                            NotificationCenter.default.publisher(
                                for: Notification.Name("GroupChanged"))
                        ) { _ in
                            SocketService.shared.restart()
                            refreshData()
                        }
                } else {
                    LoginView(authManager: authManager)
                }
            }
            .onAppear {
                authManager.checkAuthentication()
            }
        }
    }
}
