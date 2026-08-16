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

	private var groceryStore: EntityStore<GroceryItem, LocalGroceryItem>?
	private var mealStore: EntityStore<MealPlan, LocalMealPlan>?
	private var receiptStore: EntityStore<Receipt, LocalReceipt>?

	private(set) var isSyncing = false

	private init() {}

	// MARK: - Configuration

	func configure(
		modelContext: ModelContext,
		groceriesService: any GroceriesServicing,
		mealsService: any MealsServicing,
		receiptsService: any ReceiptsServicing
	) {
		self.modelContext = modelContext
		self.groceriesService = groceriesService
		self.mealsService = mealsService
		self.receiptsService = receiptsService

		let onMutate: () -> Void = { [weak self] in self?.syncIfNeeded() }

		groceryStore = EntityStore(
			entityType: .grocery,
			modelContext: modelContext,
			makeCreatePayload: { local in
				Self.encode(
					NewGroceryItem(
						id: local.localID.uuidString,
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
					isShoppingChecked: payload.isShoppingChecked
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
						id: local.localID.uuidString,
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
						id: local.localID.uuidString,
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
		let local = LocalGroceryItem(name: name, category: category)
		return groceryStore?.enqueueCreate(local: local) ?? local.toGroceryItem()
	}

	/// `isNeeded` and `isShoppingChecked` are the desired final values.
	/// The caller (GroceriesModel) is responsible for deriving them from its
	/// GroceryItemField enum (e.g. setting isShoppingChecked = false when
	/// isNeeded is being toggled, matching the current backend behavior).
	@discardableResult
	func enqueueGroceryUpdate(
		itemID: String,
		isNeeded: Bool,
		isShoppingChecked: Bool
	) -> GroceryItem? {
		groceryStore?.enqueueUpdate(
			id: itemID,
			mutate: { local in
				local.isNeeded = isNeeded
				local.isShoppingChecked = isShoppingChecked
			},
			patch: Self.encode(
				GroceryPatchPayload(isNeeded: isNeeded, isShoppingChecked: isShoppingChecked)
			))
	}

	func enqueueGroceryDelete(itemID: String) {
		groceryStore?.enqueueDelete(id: itemID)
	}

	// MARK: - Enqueue: Meals

	@discardableResult
	func enqueueMealCreate(date: String, mealDescription: String) -> MealPlan {
		let local = LocalMealPlan(date: date, mealDescription: mealDescription)
		return mealStore?.enqueueCreate(local: local) ?? local.toMealPlan()
	}

	@discardableResult
	func enqueueMealUpdate(
		mealID: String,
		mealDescription: String
	) -> MealPlan? {
		mealStore?.enqueueUpdate(
			id: mealID,
			mutate: { local in
				local.mealDescription = mealDescription
			},
			patch: Self.encode(MealPatchPayload(mealDescription: mealDescription)))
	}

	func enqueueMealDelete(mealID: String) {
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

		guard let groceryStore, let receiptStore else {
			return Receipt(
				id: UUID().uuidString, date: date,
				totalAmount: totalAmount, purchasedBy: purchasedBy,
				items: itemNames, notes: notes
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
			date: date, totalAmount: totalAmount,
			purchasedBy: purchasedBy, items: itemNames, notes: notes
		)
		return receiptStore.enqueueCreate(local: local)
	}

	@discardableResult
	func enqueueReceiptUpdate(
		receiptID: String,
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

	func enqueueReceiptDelete(receiptID: String) {
		receiptStore?.enqueueDelete(id: receiptID)
	}

	// MARK: - Merge (online fetch → upsert into SwiftData → return refreshed array)

	@discardableResult
	func mergeGroceries(_ serverItems: [GroceryItem]) -> [GroceryItem] {
		groceryStore?.merge(serverItems) ?? serverItems
	}

	@discardableResult
	func mergeMealPlans(_ serverPlans: [MealPlan]) -> [MealPlan] {
		mealStore?.merge(serverPlans) ?? serverPlans
	}

	@discardableResult
	func mergeReceipts(_ serverReceipts: [Receipt]) -> [Receipt] {
		receiptStore?.merge(serverReceipts) ?? serverReceipts
	}

	// MARK: - Single-Item Upsert (WebSocket)

	func upsertGroceryItem(_ item: GroceryItem) {
		groceryStore?.upsert(item)
	}

	func upsertMealPlan(_ plan: MealPlan) {
		mealStore?.upsert(plan)
	}

	func upsertReceipt(_ receipt: Receipt) {
		receiptStore?.upsert(receipt)
	}

	func deleteSyncedGroceryItem(id: String) {
		groceryStore?.deleteSynced(id: id)
	}

	func deleteSyncedMealPlan(id: String) {
		mealStore?.deleteSynced(id: id)
	}

	func deleteSyncedReceipt(id: String) {
		receiptStore?.deleteSynced(id: id)
	}

	// MARK: - Load All (offline read path)

	func loadAllGroceryItems() -> [GroceryItem] {
		groceryStore?.loadAll() ?? []
	}

	func loadAllMealPlans() -> [MealPlan] {
		mealStore?.loadAll() ?? []
	}

	func loadAllReceipts() -> [Receipt] {
		receiptStore?.loadAll() ?? []
	}

	// MARK: - WebSocket Filter

	/// True when there is at least one pending SyncOperation for the given entity ID.
	/// Used by SocketService to skip incoming events for locally-dirty entities.
	func hasPendingOperation(id: String) -> Bool {
		guard let context = modelContext else { return false }
		guard let uuid = UUID(uuidString: id) else { return false }
		let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
		return all.contains { $0.localID == uuid }
	}

	// MARK: - Local Reset

	/// Clears all persisted entity snapshots and pending sync work.
	/// Used when the active group context changes so stale local data does not
	/// bleed across groups.
	func clearLocalData() {
		guard let context = modelContext else { return }
		try? context.delete(model: LocalGroceryItem.self)
		try? context.delete(model: LocalMealPlan.self)
		try? context.delete(model: LocalReceipt.self)
		try? context.delete(model: SyncOperation.self)
		try? context.save()
		log("Local store cleared")
	}

	// MARK: - Payloads

	private struct GroceryPatchPayload: Codable {
		let isNeeded: Bool
		let isShoppingChecked: Bool
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