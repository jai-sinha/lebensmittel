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
	@State private var hasStartedSession = false

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
		guard !hasStartedSession else { return }
		hasStartedSession = true

		groceriesModel.replaceAll(with: SyncEngine.shared.loadAllGroceryItems())
		mealsModel.replaceAll(with: SyncEngine.shared.loadAllMealPlans())
		receiptsModel.replaceAll(with: SyncEngine.shared.loadAllReceipts())

		SocketService.shared.start(
			with: groceriesModel,
			mealsModel: mealsModel,
			receiptsModel: receiptsModel,
			shoppingModel: shoppingModel
		)

		Task {
			await GroupService.shared.migrateLegacyGroupIfNeeded()
			await sessionManager.refreshGroupContext()
			triggerBackgroundReconcile()
		}
	}

	private func triggerBackgroundReconcile() {
		Task {
			await sessionManager.refreshGroupContext()
			SocketService.shared.ensureConnected()
			await backgroundReconcile()
		}
	}

	private func backgroundReconcile() async {
		guard ConnectivityMonitor.shared.isOnline else { return }
		guard sessionManager.hasActiveGroup else { return }

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
			// Local state is already shown; no further action needed here.
		}
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(groceriesModel)
				.environment(mealsModel)
				.environment(receiptsModel)
				.environment(shoppingModel)
				.environment(sessionManager)
				.onAppear {
					sessionManager.bootstrap()
					startSession()
				}
				.onReceive(
					NotificationCenter.default.publisher(
						for: UIApplication.willEnterForegroundNotification
					)
				) { _ in
					triggerBackgroundReconcile()
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
					triggerBackgroundReconcile()
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
					triggerBackgroundReconcile()
				}
				.modelContainer(modelContainer)
		}
	}
}
