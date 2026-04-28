//
//  lebensmittelApp.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import SwiftData
import SwiftUI

@main
struct lebensmittelApp: App {
	private let modelContainer: ModelContainer

	@State private var sessionManager = SessionManager()
	@State private var groceriesModel: GroceriesModel
	@State private var mealsModel: MealsModel
	@State private var receiptsModel: ReceiptsModel
	@State private var shoppingModel: ShoppingModel

	init() {
		do {
			modelContainer = try ModelContainer(
				for:
					LocalGroceryItem.self,
				LocalMealPlan.self,
				LocalReceipt.self,
				SyncOperation.self
			)
		} catch {
			fatalError("Failed to create SwiftData ModelContainer: \(error)")
		}

		let apiClient = APIClient.shared
		let groceriesService = GroceriesService(client: apiClient)
		let mealsService = MealsService(client: apiClient)
		let receiptsService = ReceiptsService(client: apiClient)

		let groceries = GroceriesModel(service: groceriesService)
		let meals = MealsModel(service: mealsService)
		let receipts = ReceiptsModel(service: receiptsService)
		let shopping = ShoppingModel(groceriesModel: groceries)

		_groceriesModel = State(initialValue: groceries)
		_mealsModel = State(initialValue: meals)
		_receiptsModel = State(initialValue: receipts)
		_shoppingModel = State(initialValue: shopping)
		_sessionManager = State(initialValue: SessionManager())

		SyncEngine.shared.configure(
			modelContext: ModelContext(modelContainer),
			groceriesService: groceriesService,
			mealsService: mealsService,
			receiptsService: receiptsService
		)
	}

	private func startSession() {
		SyncEngine.shared.syncIfNeeded()
		SocketService.shared.start(
			with: groceriesModel,
			mealsModel: mealsModel,
			receiptsModel: receiptsModel,
			shoppingModel: shoppingModel
		)
		refreshData()
	}

	private func refreshData() {
		SyncEngine.shared.syncIfNeeded()
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
									SyncEngine.shared.syncIfNeeded()
									SocketService.shared.ensureConnected()
									refreshData()
								} catch {
									await MainActor.run {
										SyncEngine.shared.clearLocalData()
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
							SyncEngine.shared.clearLocalData()
							refreshData()
							SocketService.shared.restart()
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
		.modelContainer(modelContainer)
	}
}
