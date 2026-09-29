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

	@State private var groceriesModel: GroceriesModel
	@State private var mealsModel: MealsModel
	@State private var receiptsModel: ReceiptsModel
	@State private var shoppingModel: ShoppingModel
	@State private var groupModel: GroupModel
	@State private var hasStartedSession = false
	@State private var isReconciling = false

	init() {
		do {
			modelContainer = try ModelContainer(
				for:
					LocalGroupState.self,
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

		let groceries = GroceriesModel()
		let meals = MealsModel()
		let receipts = ReceiptsModel()
		let group = GroupModel.shared
		group.configure(modelContext: ModelContext(modelContainer))
		let shopping = ShoppingModel(groceriesModel: groceries)

		_groceriesModel = State(initialValue: groceries)
		_mealsModel = State(initialValue: meals)
		_receiptsModel = State(initialValue: receipts)
		_shoppingModel = State(initialValue: shopping)
		_groupModel = State(initialValue: group)

		SyncEngine.shared.configure(
			modelContext: ModelContext(modelContainer),
			groceriesService: groceriesService,
			mealsService: mealsService,
			receiptsService: receiptsService,
			groceriesModel: groceries,
			mealsModel: meals,
			receiptsModel: receipts,
			changesService: ChangesService(client: apiClient)
		)
	}

	private func startSession() {
		guard !hasStartedSession else { return }
		hasStartedSession = true

		SyncEngine.shared.reloadModels()

		SocketService.shared.start(with: groupModel)

		Task {
			await groupModel.bootstrap()
			triggerBackgroundReconcile()
		}
	}

	private func triggerBackgroundReconcile() {
		guard !isReconciling else { return }
		isReconciling = true
		Task {
			defer { isReconciling = false }
			await groupModel.bootstrap()
			SocketService.shared.ensureConnected()
			await backgroundReconcile()
		}
	}

	private func backgroundReconcile() async {
		guard ConnectivityMonitor.shared.isOnline else { return }
		guard groupModel.hasActiveGroup else { return }

		do {
			try await SyncEngine.shared.reconcile()
			SyncEngine.shared.syncIfNeeded()
		} catch {
			print(error)
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
				.environment(groupModel)
				.onAppear {
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
						triggerBackgroundReconcile()
					} else {
						SocketService.shared.disconnect()
					}
				}
				.onReceive(
					NotificationCenter.default.publisher(
						for: Notification.Name("GroupChanged")
					)
				) { _ in
					SyncEngine.shared.reloadModels()
					SocketService.shared.restart()
					triggerBackgroundReconcile()
				}
				.modelContainer(modelContainer)
		}
	}
}
