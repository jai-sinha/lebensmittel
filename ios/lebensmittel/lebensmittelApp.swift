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
	private let groceriesService: GroceriesService
	private let mealsService: MealsService
	private let receiptsService: ReceiptsService

	@State private var sessionManager = SessionManager()
	@State private var groceriesModel: GroceriesModel
	@State private var mealsModel: MealsModel
	@State private var receiptsModel: ReceiptsModel
	@State private var shoppingModel: ShoppingModel
	@State private var hasStartedAuthenticatedSession = false

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
		self.groceriesService = groceriesService
		self.mealsService = mealsService
		self.receiptsService = receiptsService

		let groceries = GroceriesModel(service: groceriesService)
		let meals = MealsModel(service: mealsService)
		let receipts = ReceiptsModel(service: receiptsService)
		let shopping = ShoppingModel(
			groceriesModel: groceries,
			receiptsService: receiptsService
		)

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
		guard !hasStartedAuthenticatedSession else { return }
		hasStartedAuthenticatedSession = true

		Task {
			await hydrateFromServerAndStartSocket()
		}
	}

	private func hydrateFromServerAndStartSocket() async {
		do {
			async let groceriesTask = groceriesService.fetchGroceries()
			async let mealsTask = mealsService.fetchMealPlans()
			async let receiptsTask = receiptsService.fetchReceipts()

			let groceries = try await groceriesTask
			let meals = try await mealsTask
			let receipts = try await receiptsTask

			let mergedGroceries = SyncEngine.shared.mergeGroceries(groceries)
			let mergedMeals = SyncEngine.shared.mergeMealPlans(meals)
			let mergedReceipts = SyncEngine.shared.mergeReceipts(receipts)

			groceriesModel.replaceAll(with: mergedGroceries)
			mealsModel.replaceAll(with: mergedMeals)
			receiptsModel.replaceAll(with: mergedReceipts)
			SocketService.shared.start(
				with: groceriesModel,
				mealsModel: mealsModel,
				receiptsModel: receiptsModel,
				shoppingModel: shoppingModel
			)
			SyncEngine.shared.syncIfNeeded()
		} catch {
			groceriesModel.fetchGroceries()
			mealsModel.fetchMealPlans()
			receiptsModel.fetchReceipts()
			SocketService.shared.start(
				with: groceriesModel,
				mealsModel: mealsModel,
				receiptsModel: receiptsModel,
				shoppingModel: shoppingModel
			)
		}
	}

	private func refreshData(triggerSync: Bool = true) {
		if triggerSync {
			SyncEngine.shared.syncIfNeeded()
		}
		Task {
			await hydrateFromServerAndStartSocket()
		}
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

						.onChange(of: ConnectivityMonitor.shared.isOnline) { _, isOnline in
							if isOnline {
								SocketService.shared.restart()
							} else {
								SocketService.shared.disconnect()
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
			.onChange(of: sessionManager.isAuthenticated) { _, isAuthenticated in
				if !isAuthenticated {
					hasStartedAuthenticatedSession = false
				}
			}
		}
		.modelContainer(modelContainer)
	}
}
