//
//  lebensmittelApp.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftUI

@main
struct lebensmittelApp: App {
	@State private var sessionManager = SessionManager()
	@State private var groceriesModel: GroceriesModel
	@State private var mealsModel: MealsModel
	@State private var receiptsModel: ReceiptsModel
	@State private var shoppingModel: ShoppingModel

	init() {
		let groceriesService = GroceriesService()
		let mealsService = MealsService()
		let receiptsService = ReceiptsService()
		let shoppingService = ShoppingService()

		let groceries = GroceriesModel(service: groceriesService)
		_groceriesModel = State(initialValue: groceries)
		_mealsModel = State(initialValue: MealsModel(service: mealsService))
		_receiptsModel = State(initialValue: ReceiptsModel(service: receiptsService))
		_shoppingModel = State(
			initialValue: ShoppingModel(groceriesModel: groceries, service: shoppingService)
		)
		_sessionManager = State(initialValue: SessionManager())
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
				if sessionManager.isCheckingAuth {
					ProgressView("Loading...")
				} else if sessionManager.isAuthenticated {
					ContentView()
						.environment(groceriesModel)
						.environment(mealsModel)
						.environment(receiptsModel)
						.environment(shoppingModel)
						.environment(sessionManager)
						.onAppear {
							startSession()
						}
						.onReceive(
							NotificationCenter.default.publisher(
								for: UIApplication.willEnterForegroundNotification
							)
						) { _ in
							Task {
								do {
									_ = try await AuthManager.shared.ensureAuthenticated()
									SocketService.shared.ensureConnected()
									refreshData()
								} catch {
									await MainActor.run {
										sessionManager.clearLocalState()
									}
								}
							}
						}
						.onReceive(
							NotificationCenter.default.publisher(
								for: Notification.Name("GroupChanged")
							)
						) { _ in
							SocketService.shared.restart()
							refreshData()
						}
				} else if sessionManager.isGuest {
					ContentView()
						.environment(groceriesModel)
						.environment(mealsModel)
						.environment(receiptsModel)
						.environment(shoppingModel)
						.environment(sessionManager)
				} else {
					GuestHomeView(sessionManager: sessionManager)
				}
			}
			.onAppear {
				sessionManager.checkAuthentication()
			}
		}
	}
}
