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
    var isGuest = false
    var currentUser: User?
    var currentUserGroups: [AuthGroup] = []
    var currentUserActiveGroupId: String?
    var currentGroupUsers: [GroupUser] = []
    var isCheckingAuth = true
    var errorMessage: String?

    func checkAuthentication() {
        Task {
            await refreshState()
            await MainActor.run {
                self.isCheckingAuth = false
            }
        }
    }

    func refreshState() async {
        do {
            let isAuth = try await AuthManager.shared.isAuthenticated()

            if isAuth {
                let user = try await AuthManager.shared.getCurrentUser()
                let userGroups = try await AuthManager.shared.getUserGroups()
                let userActiveGroupId = try await AuthManager.shared.getActiveGroupId()
                let groupUsers = try await AuthManager.shared.getUsersInGroup()

                await MainActor.run {
                    self.isAuthenticated = true
                    self.currentUser = user
                    self.currentUserGroups = userGroups
                    self.currentUserActiveGroupId = userActiveGroupId
                    self.currentGroupUsers = groupUsers
                    self.errorMessage = nil
                }
            } else {
                await MainActor.run {
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.currentUserGroups = []
                    self.currentUserActiveGroupId = nil
                    self.currentGroupUsers = []
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isAuthenticated = false
            }
        }
    }

    func logout() {
        Task {
            do {
                try await AuthManager.shared.logout()
                await MainActor.run {
                    self.clearLocalState()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Clears only the observable UI state. Use this when the underlying
    /// keychain/storage has already been wiped (e.g. after deleteAccount,
    /// which calls logout() internally before returning).
    func clearLocalState() {
        isAuthenticated = false
        isGuest = false
        currentUser = nil
        currentUserGroups = []
        currentUserActiveGroupId = nil
        currentGroupUsers = []
        errorMessage = nil
    }

    /// Skips sign-in and enters the app in a read-only guest state.
    func continueAsGuest() {
        isGuest = true
    }

    /// Called when a guest taps "Sign In" from within the app; returns
    /// them to GuestHomeView so they can authenticate properly.
    func exitGuestMode() {
        isGuest = false
    }
}

@main
struct lebensmittelApp: App {
    @State private var authManager = AuthStateManager()
    @State private var groceriesModel: GroceriesModel
    @State private var mealsModel: MealsModel
    @State private var receiptsModel: ReceiptsModel
    @State private var shoppingModel: ShoppingModel

    init() {
        let groceries = GroceriesModel()
        _groceriesModel = State(initialValue: groceries)
        _mealsModel = State(initialValue: MealsModel())
        _receiptsModel = State(initialValue: ReceiptsModel())
        _shoppingModel = State(initialValue: ShoppingModel(groceriesModel: groceries))
        _authManager = State(initialValue: AuthStateManager())
    }

    private func startSession() {
        SocketService.shared.start(
            with: groceriesModel,
            mealsModel: mealsModel,
            receiptsModel: receiptsModel,
            shoppingModel: shoppingModel
        )
        groceriesModel.fetchGroceries()
        mealsModel.fetchMealPlans()
        receiptsModel.fetchReceipts()
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
                            startSession()
                            authManager.checkAuthentication()
                        }
                        .onReceive(
                            NotificationCenter.default.publisher(
                                for: UIApplication.willEnterForegroundNotification)
                        ) { _ in
                            SocketService.shared.ensureConnected()
                            refreshData()
                        }
                        .onReceive(
                            NotificationCenter.default.publisher(
                                for: Notification.Name("GroupChanged"))
                        ) { _ in
                            print("Group Changed! Group ID: \(authManager.currentUserActiveGroupId ?? "nil")")
                            SocketService.shared.restart()
                            refreshData()
                        }
                } else if authManager.isGuest {
                    // Guest mode: show the full tab UI but with no data loaded.
                    // Each feature view shows an inline sign-in prompt instead of content.
                    ContentView()
                        .environment(groceriesModel)
                        .environment(mealsModel)
                        .environment(receiptsModel)
                        .environment(shoppingModel)
                        .environment(authManager)
                } else {
                    GuestHomeView(authManager: authManager)
                }
            }
            .onAppear {
                authManager.checkAuthentication()
            }
        }
    }
}
