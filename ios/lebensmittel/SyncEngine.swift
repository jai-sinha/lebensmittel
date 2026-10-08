//
//  SyncEngine.swift
//  lebensmittel
//
//  Created by Jai Sinha on 3/25/26.
//

import Foundation
import SwiftData

// MARK: - SyncEngine

/// Owns all writes to SwiftData and all outbound network sync.
/// Feature models call the enqueueXxx methods; SyncEngine handles persistence,
/// the durable operation queue, conflict resolution, ID remapping, and retries.
///
/// The per-entity lifecycle lives in three generic `EntityStore` instances
/// (grocery / meal / receipt); this shell owns the operation queue drain and
/// routes each operation to the store for its entity type.

@MainActor
final class SyncEngine {
	static let shared = SyncEngine()

	/// Set to true to enable verbose logging — mirrors SocketService.verbose.
	@MainActor static var verbose = false

	private var modelContext: ModelContext?
	private var groceriesService: (any GroceriesServicing)?
	private var mealsService: (any MealsServicing)?
	private var receiptsService: (any ReceiptsServicing)?
	private var changesService: (any ChangesServicing)?

	private var groceryStore: EntityStore<GroceryItem, LocalGroceryItem>?
	private var mealStore: EntityStore<MealPlan, LocalMealPlan>?
	private var receiptStore: EntityStore<Receipt, LocalReceipt>?

	private var groceriesModel: GroceriesModel?
	private var mealsModel: MealsModel?
	private var receiptsModel: ReceiptsModel?
	private let groupModel: GroupModel

	private(set) var isSyncing = false
	private var reconcileTask: Task<Void, Error>?

	private init() {
		groupModel = .shared
	}

	// MARK: - Configuration

	func configure(
		modelContext: ModelContext,
		groceriesService: any GroceriesServicing,
		mealsService: any MealsServicing,
		receiptsService: any ReceiptsServicing,
		groceriesModel: GroceriesModel,
		mealsModel: MealsModel,
		receiptsModel: ReceiptsModel,
		changesService: any ChangesServicing
	) {
		self.modelContext = modelContext
		self.groceriesService = groceriesService
		self.mealsService = mealsService
		self.receiptsService = receiptsService
		self.changesService = changesService
		self.groceriesModel = groceriesModel
		self.mealsModel = mealsModel
		self.receiptsModel = receiptsModel

		let onMutate: () -> Void = { [weak self] in self?.syncIfNeeded() }

		groceryStore = EntityStore(
			entityType: .grocery,
			modelContext: modelContext,
			makeCreatePayload: { local in
				Self.encode(
					NewGroceryItem(
						id: local.localID,
						name: local.name,
						category: local.category,
						isNeeded: local.isNeeded,
						isShoppingChecked: local.isShoppingChecked
					))
			},
			createRemote: { data in
				let payload = try JSONDecoder().decode(NewGroceryItem.self, from: data)
				return try await groceriesService.createGroceryItem(payload)
			},
			updateRemote: { id, data in
				let payload = try JSONDecoder().decode(GroceryPatchPayload.self, from: data)
				try await groceriesService.updateGroceryItem(
					id: id,
					isNeeded: payload.isNeeded,
					isShoppingChecked: payload.isShoppingChecked,
					category: payload.category,
					name: payload.name
				)
			},
			deleteRemote: { id in
				try await groceriesService.deleteGroceryItem(id: id)
			},
			onMutate: onMutate
		)

		mealStore = EntityStore(
			entityType: .meal,
			modelContext: modelContext,
			makeCreatePayload: { local in
				Self.encode(
					NewMealPlan(
						id: local.localID,
						date: local.date,
						mealDescription: local.mealDescription
					))
			},
			createRemote: { data in
				let payload = try JSONDecoder().decode(NewMealPlan.self, from: data)
				return try await mealsService.createMealPlan(payload)
			},
			updateRemote: { id, data in
				let payload = try JSONDecoder().decode(MealPatchPayload.self, from: data)
				try await mealsService.updateMealPlan(id: id, mealDescription: payload.mealDescription)
			},
			deleteRemote: { id in
				try await mealsService.deleteMealPlan(id: id)
			},
			onMutate: onMutate
		)

		receiptStore = EntityStore(
			entityType: .receipt,
			modelContext: modelContext,
			makeCreatePayload: { local in
				Self.encode(
					NewReceipt(
						id: local.localID,
						date: local.date,
						totalAmount: local.totalAmount,
						purchasedBy: local.purchasedBy,
						items: local.items,
						notes: local.notes
					))
			},
			createRemote: { data in
				let payload = try JSONDecoder().decode(NewReceipt.self, from: data)
				return try await receiptsService.createReceipt(payload)
			},
			updateRemote: { id, data in
				let payload = try JSONDecoder().decode(ReceiptPatchPayload.self, from: data)
				try await receiptsService.updateReceipt(
					id: id,
					price: payload.totalAmount,
					purchasedBy: payload.purchasedBy,
					notes: payload.notes ?? ""
				)
			},
			deleteRemote: { id in
				try await receiptsService.deleteReceipt(id: id)
			},
			onMutate: onMutate
		)

		log("Configured")
	}

	// MARK: - Sync Trigger

	func syncIfNeeded() {
		guard ConnectivityMonitor.shared.isOnline else {
			log("Offline, skipping")
			return
		}
		Task {
			await drainQueue()
		}
	}

	// MARK: - Queue Drain

	private func drainQueue() async {
		guard !isSyncing else { return }

		isSyncing = true
		defer {
			isSyncing = false
		}

		guard let context = modelContext else { return }

		let descriptor = FetchDescriptor<SyncOperation>(
			sortBy: [SortDescriptor(\.createdAt, order: .forward)]
		)
		guard let ops = try? context.fetch(descriptor) else {
			log("Failed to fetch pending operations")
			return
		}
		guard !ops.isEmpty else {
			log("Queue empty")
			return
		}

		log("Processing \(ops.count) operation(s)")

		for op in ops {
			let opID = op.id
			let entityType = op.entityType
			let operationType = op.operationType

			if op.retryCount >= 3 {
				log("Operation \(opID) hit max retries — discarding")
				context.delete(op)
				try? context.save()
				continue
			}

			do {
				try await process(op)
				context.delete(op)
				try? context.save()
				log("✓ \(entityType.rawValue) \(operationType.rawValue) \(opID)")
			} catch {
				op.retryCount += 1
				op.lastError = error.localizedDescription
				try? context.save()
				log(
					"✗ \(entityType.rawValue) \(operationType.rawValue) — \(error.localizedDescription). Retry \(op.retryCount)/3. Stopping."
				)
				return
			}
		}

		log("Queue drained")
	}

	// MARK: - Operation Processing

	private func process(_ op: SyncOperation) async throws {
		switch op.entityType {
		case .grocery:
			guard let groceryStore else { throw SyncError.notConfigured }
			try await groceryStore.process(op)
		case .meal:
			guard let mealStore else { throw SyncError.notConfigured }
			try await mealStore.process(op)
		case .receipt:
			guard let receiptStore else { throw SyncError.notConfigured }
			try await receiptStore.process(op)
		}
	}

	// MARK: - Enqueue: Groceries

	@discardableResult
	func enqueueGroceryCreate(name: String, category: String) -> GroceryItem {
		let local = LocalGroceryItem(
			groupId: groupModel.getActiveGroupId() ?? "",
			name: name,
			category: category
		)
		return groceryStore?.enqueueCreate(local: local) ?? local.toGroceryItem()
	}

	@discardableResult
	func enqueueGroceryUpdate(
		itemID: UUID,
		isNeeded: Bool,
		isShoppingChecked: Bool,
		category: String? = nil,
		name: String? = nil

	) -> GroceryItem? {
		groceryStore?.enqueueUpdate(
			id: itemID,
			mutate: { local in
				local.isNeeded = isNeeded
				local.isShoppingChecked = isShoppingChecked
				if let category { local.category = category }
				if let name { local.name = name }
			},
			patch: Self.encode(
				GroceryPatchPayload(
					isNeeded: isNeeded,
					isShoppingChecked: isShoppingChecked,
					category: category,
					name: name
				)
			))
	}

	func enqueueGroceryDelete(itemID: UUID) {
		groceryStore?.enqueueDelete(id: itemID)
	}

	// MARK: - Enqueue: Meals

	@discardableResult
	func enqueueMealCreate(date: String, mealDescription: String) -> MealPlan {
		let local = LocalMealPlan(
			groupId: groupModel.getActiveGroupId() ?? "",
			date: date,
			mealDescription: mealDescription
		)
		return mealStore?.enqueueCreate(local: local) ?? local.toMealPlan()
	}

	@discardableResult
	func enqueueMealUpdate(
		mealID: UUID,
		mealDescription: String
	) -> MealPlan? {
		mealStore?.enqueueUpdate(
			id: mealID,
			mutate: { local in
				local.mealDescription = mealDescription
			},
			patch: Self.encode(MealPatchPayload(mealDescription: mealDescription)))
	}

	func enqueueMealDelete(mealID: UUID) {
		mealStore?.enqueueDelete(id: mealID)
	}

	// MARK: - Enqueue: Receipts

	/// Replicates the server's receipt-creation transaction locally:
	/// snapshots the checked items, creates the receipt, resets grocery flags.
	/// A single SyncOperation with the explicit items list is enqueued;
	/// no separate PATCH ops are created for the grocery flag resets — the
	/// server performs those atomically as part of the receipt create transaction.
	@discardableResult
	func enqueueReceiptCreate(
		date: String,
		totalAmount: Double,
		purchasedBy: String,
		notes: String?,
		checkedItems: [GroceryItem]
	) -> Receipt {
		let itemNames = checkedItems.map { $0.name }
		let activeGroupID = groupModel.getActiveGroupId() ?? ""

		guard let groceryStore, let receiptStore else {
			return Receipt(
				id: UUID(), date: date,
				totalAmount: totalAmount, purchasedBy: purchasedBy,
				items: itemNames, notes: notes,
				groupId: activeGroupID
			)
		}

		for item in checkedItems {
			groceryStore.enqueueUpdate(
				id: item.id,
				mutate: { grocery in
					grocery.isNeeded = false
					grocery.isShoppingChecked = false
				},
				patch: Self.encode(GroceryPatchPayload(isNeeded: false, isShoppingChecked: false)))
		}

		let local = LocalReceipt(
			groupId: activeGroupID,
			date: date, totalAmount: totalAmount,
			purchasedBy: purchasedBy, items: itemNames, notes: notes
		)
		return receiptStore.enqueueCreate(local: local)
	}

	@discardableResult
	func enqueueReceiptUpdate(
		receiptID: UUID,
		totalAmount: Double,
		purchasedBy: String,
		notes: String
	) -> Receipt? {
		receiptStore?.enqueueUpdate(
			id: receiptID,
			mutate: { local in
				local.totalAmount = totalAmount
				local.purchasedBy = purchasedBy
				local.notes = notes
			},
			patch: Self.encode(
				ReceiptPatchPayload(
					totalAmount: totalAmount,
					purchasedBy: purchasedBy,
					notes: notes
				)))
	}

	func enqueueReceiptDelete(receiptID: UUID) {
		receiptStore?.enqueueDelete(id: receiptID)
	}

	// MARK: - Apply (server-originated changes)

	/// Apply upserts, ignore echoes
	func applyServerUpsert(_ item: GroceryItem) {
		guard groceryStore?.applyServerChange(item) == true else { return }
		groceriesModel?.addItem(item)
	}

	func applyServerUpsert(_ plan: MealPlan) {
		guard mealStore?.applyServerChange(plan) == true else { return }
		mealsModel?.addMealPlan(plan)
	}

	func applyServerUpsert(_ receipt: Receipt) {
		guard receiptStore?.applyServerChange(receipt) == true else { return }
		receiptsModel?.addReceipt(receipt)
	}

	func applyServerDelete(type: SyncEntityType, id: UUID) {
		switch type {
		case .grocery:
			guard groceryStore?.applyServerDelete(id: id) == true else { return }
			groceriesModel?.removeItem(withId: id)
		case .meal:
			guard mealStore?.applyServerDelete(id: id) == true else { return }
			mealsModel?.removeMealPlan(withId: id)
		case .receipt:
			guard receiptStore?.applyServerDelete(id: id) == true else { return }
			receiptsModel?.deleteReceipt(withId: id)
		}
	}

	// MARK: - Reconcile (cursor-based catch-up)

	/// Bring the local copy up to date with the server for the active group
	func reconcile(forceSnapshot: Bool = false) async throws {
		// concurrent calls share a result
		if let running = reconcileTask {
			try await running.value
			guard forceSnapshot else { return }
		}
		let task = Task { [weak self] in
			guard let self else { return }
			try await self.performReconcile(forceSnapshot: forceSnapshot)
		}
		reconcileTask = task
		defer { reconcileTask = nil }
		try await task.value
	}

	private func performReconcile(forceSnapshot: Bool) async throws {
		guard let groupID = groupModel.getActiveGroupId() else { return }
		guard let changesService else { throw SyncError.notConfigured }

		let response = try await changesService.fetchChanges(
			afterSeq: forceSnapshot ? nil : cursor(for: groupID)
		)

		// The group can change while the request is in flight; applying another
		// group's entities now would show the wrong data on screen.
		guard groupID == groupModel.getActiveGroupId() else { return }

		if response.isFull {
			// A full set is authoritative: the merge drops the rows it no longer
			// lists, and the models are replaced with what survives.
			groceriesModel?.replaceAll(
				with: groceryStore?.merge(response.grocery, for: groupID) ?? [])
			mealsModel?.replaceAll(with: mealStore?.merge(response.meal, for: groupID) ?? [])
			receiptsModel?.replaceAll(
				with: receiptStore?.merge(response.receipt, for: groupID) ?? [])
		} else {
			response.grocery.forEach { applyServerUpsert($0) }
			response.deletedIds.grocery.forEach { applyServerDelete(type: .grocery, id: $0) }
			response.meal.forEach { applyServerUpsert($0) }
			response.deletedIds.meal.forEach { applyServerDelete(type: .meal, id: $0) }
			response.receipt.forEach { applyServerUpsert($0) }
			response.deletedIds.receipt.forEach { applyServerDelete(type: .receipt, id: $0) }
		}

		setCursor(response.nextSeq, for: groupID)
		_ = try? await groupModel.refreshActiveGroup()
		log("Reconciled to seq \(response.nextSeq)")
	}

	// MARK: - Cursor (per-group sync position)

	private static func cursorKey(for groupID: String) -> String {
		"syncSeq.\(groupID)"
	}

	private func cursor(for groupID: String) -> Int64? {
		guard let raw = UserDefaults.standard.object(forKey: Self.cursorKey(for: groupID)) as? NSNumber
		else { return nil }
		return raw.int64Value
	}

	private func setCursor(_ seq: Int64, for groupID: String) {
		UserDefaults.standard.set(seq, forKey: Self.cursorKey(for: groupID))
	}

	// MARK: - Load All (offline read path)

	/// Loads the active group's local entities from SwiftData.
	func loadAllGroceryItems() -> [GroceryItem] {
		guard let groupID = groupModel.getActiveGroupId() else { return [] }
		return groceryStore?.loadAll(for: groupID) ?? []
	}

	func loadAllMealPlans() -> [MealPlan] {
		guard let groupID = groupModel.getActiveGroupId() else { return [] }
		return mealStore?.loadAll(for: groupID) ?? []
	}

	func loadAllReceipts() -> [Receipt] {
		guard let groupID = groupModel.getActiveGroupId() else { return [] }
		return receiptStore?.loadAll(for: groupID) ?? []
	}

	/// Republish the local store into the feature models, for when it changed locally
	func reloadModels() {
		groceriesModel?.replaceAll(with: loadAllGroceryItems())
		mealsModel?.replaceAll(with: loadAllMealPlans())
		receiptsModel?.replaceAll(with: loadAllReceipts())
	}

	// MARK: - Payloads

	private struct GroceryPatchPayload: Codable {
		let isNeeded: Bool
		let isShoppingChecked: Bool
		var category: String? = nil
		var name: String? = nil
	}

	private struct MealPatchPayload: Codable {
		let mealDescription: String
	}

	private struct ReceiptPatchPayload: Codable {
		let totalAmount: Double
		let purchasedBy: String
		let notes: String?
	}

	private static func encode<T: Encodable>(_ value: T) -> Data {
		(try? JSONEncoder().encode(value)) ?? Data()
	}

	private func log(_ msg: String) {
		if Self.verbose { print("[SyncEngine] \(msg)") }
	}
}

// MARK: - Errors

enum SyncError: LocalizedError {
	case missingServerID
	case notConfigured

	var errorDescription: String? {
		switch self {
		case .missingServerID: "Update operation missing server ID"
		case .notConfigured: "Sync engine is not configured"
		}
	}
}
