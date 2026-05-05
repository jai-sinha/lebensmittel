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

		// Load last-known state from SwiftData immediately — no spinner.
		groceriesModel.replaceAll(with: SyncEngine.shared.loadAllGroceryItems())
		mealsModel.replaceAll(with: SyncEngine.shared.loadAllMealPlans())
		receiptsModel.replaceAll(with: SyncEngine.shared.loadAllReceipts())

		SocketService.shared.start(
			with: groceriesModel,
			mealsModel: mealsModel,
			receiptsModel: receiptsModel,
			shoppingModel: shoppingModel
		)

		// Reconcile with server in background — silently updates models when done.
		Task { await backgroundReconcile() }
	}

	/// Fetches the latest server state and merges it into SwiftData + models.
	/// Never sets isLoading — updates are silent. Safe to call from any trigger.
	private func backgroundReconcile() async {
		guard ConnectivityMonitor.shared.isOnline else { return }
		do {
			async let g = groceriesService.fetchGroceries()
			async let m = mealsService.fetchMealPlans()
			async let r = receiptsService.fetchReceipts()
			let (groceries, meals, receipts) = try await (g, m, r)

			groceriesModel.replaceAll(with: SyncEngine.shared.mergeGroceries(groceries))
			mealsModel.replaceAll(with: SyncEngine.shared.mergeMealPlans(meals))
			receiptsModel.replaceAll(with: SyncEngine.shared.mergeReceipts(receipts))
			SyncEngine.shared.syncIfNeeded()
		} catch {
			// Network unavailable — local data is already displayed, nothing to do.
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
									await backgroundReconcile()
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
								for: Notification.Name("syncEngineDidFinish")
							)
						) { _ in
							Task { await backgroundReconcile() }
						}
						.onReceive(
							NotificationCenter.default.publisher(
								for: Notification.Name("GroupChanged")
							)
						) { _ in
							SyncEngine.shared.clearLocalData()
							groceriesModel.replaceAll(with: [])
							mealsModel.replaceAll(with: [])
							receiptsModel.replaceAll(with: [])
							SocketService.shared.restart()
							Task { await backgroundReconcile() }
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
