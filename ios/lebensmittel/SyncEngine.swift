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

@MainActor
final class SyncEngine {
	static let shared = SyncEngine()

	/// Set to true to enable verbose logging — mirrors SocketService.verbose.
	@MainActor static var verbose = false

	private var modelContext: ModelContext?
	private var groceriesService: (any GroceriesServicing)?
	private var mealsService: (any MealsServicing)?
	private var receiptsService: (any ReceiptsServicing)?
	private(set) var isSyncing = false

	private struct ReceiptCreatePayload: Codable {
		let date: String
		let totalAmount: Double
		let purchasedBy: String
		let notes: String?
		let items: [String]
	}

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
		log("Configured")
	}

	// MARK: - Sync Trigger

	func syncIfNeeded() {
		guard !isSyncing else {
			log("Already syncing, skipping")
			return
		}
		guard ConnectivityMonitor.shared.isOnline else {
			log("Offline, skipping")
			return
		}
		guard SocketService.shared.isConnectedForSync else {
			log("Socket disconnected, skipping")
			return
		}
		Task {
			await drainQueue()
		}
	}

	// MARK: - Queue Drain

	private func drainQueue() async {
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

		isSyncing = true
		defer {
			isSyncing = false
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

	}

	// MARK: - Operation Processing

	private func process(_ op: SyncOperation) async throws {
		switch op.operationType {
		case .create: try await processCreate(op)
		case .update: try await processUpdate(op)
		case .delete: try await processDelete(op)
		}
	}

	private func processCreate(_ op: SyncOperation) async throws {
		guard let context = modelContext else { return }

		let serverID: String
		switch op.entityType {
		case .grocery:
			guard let groceriesService else { throw SyncError.notConfigured }
			let payload: NewGroceryItem
			if let local = findLocalGroceryItem(byLocalID: op.localID) {
				payload = NewGroceryItem(
					name: local.name,
					category: local.category,
					isNeeded: local.isNeeded,
					isShoppingChecked: local.isShoppingChecked
				)
			} else {
				payload = try JSONDecoder().decode(NewGroceryItem.self, from: op.payload)
			}

			let created = try await groceriesService.createGroceryItem(
				name: payload.name,
				category: payload.category
			)
			serverID = created.id
			findLocalGroceryItem(byLocalID: op.localID)?.applyServerValues(created)

		case .meal:
			guard let mealsService else { throw SyncError.notConfigured }
			let payload: NewMealPlan
			if let local = findLocalMealPlan(byLocalID: op.localID) {
				payload = NewMealPlan(date: local.date, mealDescription: local.mealDescription)
			} else {
				payload = try JSONDecoder().decode(NewMealPlan.self, from: op.payload)
			}

			let created = try await mealsService.createMealPlan(
				date: payload.date,
				mealDescription: payload.mealDescription
			)
			serverID = created.id
			findLocalMealPlan(byLocalID: op.localID)?.applyServerValues(created)

		case .receipt:
			guard let receiptsService else { throw SyncError.notConfigured }
			let payload = try JSONDecoder().decode(ReceiptCreatePayload.self, from: op.payload)
			let created = try await receiptsService.createReceipt(
				NewReceipt(
					date: payload.date,
					totalAmount: payload.totalAmount,
					purchasedBy: payload.purchasedBy,
					items: payload.items,
					notes: payload.notes
				)
			)
			serverID = created.id
			findLocalReceipt(byLocalID: op.localID)?.applyServerValues(created)
		}

		fetchOps(for: op.localID, after: op.createdAt).forEach { $0.serverID = serverID }

		try? context.save()
	}

	private func processUpdate(_ op: SyncOperation) async throws {
		guard let context = modelContext else { return }
		guard let serverID = op.serverID else { throw SyncError.missingServerID }

		switch op.entityType {
		case .grocery:
			guard let groceriesService else { throw SyncError.notConfigured }
			let payload = try JSONDecoder().decode(GroceryPatchPayload.self, from: op.payload)
			try await groceriesService.updateGroceryItem(
				id: serverID,
				isNeeded: payload.isNeeded,
				isShoppingChecked: payload.isShoppingChecked
			)

		case .meal:
			guard let mealsService else { throw SyncError.notConfigured }
			let payload = try JSONDecoder().decode(MealPatchPayload.self, from: op.payload)
			try await mealsService.updateMealPlan(
				id: serverID,
				mealDescription: payload.mealDescription
			)

		case .receipt:
			guard let receiptsService else { throw SyncError.notConfigured }
			let payload = try JSONDecoder().decode(ReceiptPatchPayload.self, from: op.payload)
			try await receiptsService.updateReceipt(
				id: serverID,
				price: payload.totalAmount,
				purchasedBy: payload.purchasedBy,
				notes: payload.notes ?? ""
			)
		}

		markSynced(entityType: op.entityType, serverID: serverID)
		try? context.save()
	}

	private func processDelete(_ op: SyncOperation) async throws {
		guard let context = modelContext else { return }

		guard let serverID = op.serverID else {
			deleteLocalEntity(entityType: op.entityType, localID: op.localID)
			try? context.save()
			return
		}

		switch op.entityType {
		case .grocery:
			guard let groceriesService else { throw SyncError.notConfigured }
			try await groceriesService.deleteGroceryItem(id: serverID)
		case .meal:
			guard let mealsService else { throw SyncError.notConfigured }
			try await mealsService.deleteMealPlan(id: serverID)
		case .receipt:
			guard let receiptsService else { throw SyncError.notConfigured }
			try await receiptsService.deleteReceipt(id: serverID)
		}

		deleteLocalEntity(entityType: op.entityType, localID: op.localID)
		try? context.save()
	}

	// MARK: - Enqueue: Groceries

	@discardableResult
	func enqueueGroceryCreate(name: String, category: String) -> GroceryItem {
		let local = LocalGroceryItem(name: name, category: category)
		insertCreate(
			local,
			entityType: .grocery,
			localID: local.localID,
			encodable: NewGroceryItem(name: name, category: category)
		)
		return local.toGroceryItem()
	}

	/// `isNeeded` and `isShoppingChecked` are the desired final values.
	/// The caller (GroceriesModel) is responsible for deriving them from its
	/// GroceryItemField enum (e.g. setting isShoppingChecked = false when
	/// isNeeded is being toggled, matching the current backend behaviour).
	@discardableResult
	func enqueueGroceryUpdate(
		itemID: String,
		isNeeded: Bool,
		isShoppingChecked: Bool
	) -> GroceryItem? {
		guard let local = findLocalGroceryItem(byModelID: itemID) else { return nil }

		local.isNeeded = isNeeded
		local.isShoppingChecked = isShoppingChecked

		if local.syncStatus == .pendingCreate {
			// Pending-create: just update local fields. processCreate regenerates
			// the payload from the current entity state at sync time.
			try? modelContext?.save()
		} else {
			local.syncStatus = .pendingUpdate
			upsertUpdateOp(
				for: local.localID,
				serverID: local.serverID,
				entityType: .grocery,
				payloadDict: ["isNeeded": isNeeded, "isShoppingChecked": isShoppingChecked]
			)
		}
		return local.toGroceryItem()
	}

	func enqueueGroceryDelete(itemID: String) {
		guard let local = findLocalGroceryItem(byModelID: itemID) else { return }
		enqueueDelete(for: local, entityType: .grocery)
	}

	// MARK: - Enqueue: Meals

	@discardableResult
	func enqueueMealCreate(date: String, mealDescription: String) -> MealPlan {
		let local = LocalMealPlan(date: date, mealDescription: mealDescription)
		insertCreate(
			local,
			entityType: .meal,
			localID: local.localID,
			encodable: NewMealPlan(date: date, mealDescription: mealDescription)
		)
		return local.toMealPlan()
	}

	@discardableResult
	func enqueueMealUpdate(
		mealID: String,
		mealDescription: String
	) -> MealPlan? {
		guard let local = findLocalMealPlan(byModelID: mealID) else { return nil }

		local.mealDescription = mealDescription

		if local.syncStatus == .pendingCreate {
			// Pending-create: just update local fields. processCreate regenerates
			// the payload from the current entity state at sync time.
			try? modelContext?.save()
		} else {
			local.syncStatus = .pendingUpdate
			upsertUpdateOp(
				for: local.localID,
				serverID: local.serverID,
				entityType: .meal,
				payloadDict: ["mealDescription": mealDescription]
			)
		}
		return local.toMealPlan()
	}

	func enqueueMealDelete(mealID: String) {
		guard let local = findLocalMealPlan(byModelID: mealID) else { return }
		enqueueDelete(for: local, entityType: .meal)
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
		guard let context = modelContext else {
			return Receipt(
				id: UUID().uuidString, date: date,
				totalAmount: totalAmount, purchasedBy: purchasedBy,
				items: [], notes: notes
			)
		}

		let itemNames = checkedItems.map { $0.name }

		let local = LocalReceipt(
			date: date, totalAmount: totalAmount,
			purchasedBy: purchasedBy, items: itemNames, notes: notes
		)
		context.insert(local)

		// Reset grocery flags locally and queue follow-up updates for already-synced
		// groceries. The server applies these resets when the receipt is created,
		// but websocket ordering is not guaranteed, so we still need queued PATCHes
		// to clear the local pending state deterministically after reconnect.
		for item in checkedItems {
			guard let grocery = findLocalGroceryItem(byModelID: item.id) else { continue }
			grocery.isNeeded = false
			grocery.isShoppingChecked = false
			if grocery.syncStatus == .synced {
				grocery.syncStatus = .pendingUpdate
				upsertUpdateOp(
					for: grocery.localID,
					serverID: grocery.serverID,
					entityType: .grocery,
					payloadDict: ["isNeeded": false, "isShoppingChecked": false]
				)
			}
		}

		// Payload includes explicit items list (requires backend change to POST /api/receipts).
		let payload =
			(try? JSONEncoder().encode(
				ReceiptCreatePayload(
					date: date, totalAmount: totalAmount,
					purchasedBy: purchasedBy, notes: notes, items: itemNames
				)
			)) ?? Data()

		context.insert(
			SyncOperation(
				entityType: .receipt,
				operationType: .create,
				payload: payload,
				localID: local.localID
			))
		persist()
		return local.toReceipt()
	}

	@discardableResult
	func enqueueReceiptUpdate(
		receiptID: String,
		totalAmount: Double,
		purchasedBy: String,
		notes: String
	) -> Receipt? {
		guard let local = findLocalReceipt(byModelID: receiptID) else { return nil }

		local.totalAmount = totalAmount
		local.purchasedBy = purchasedBy
		local.notes = notes

		if local.syncStatus == .pendingCreate {
			try? modelContext?.save()
		} else {
			local.syncStatus = .pendingUpdate
			upsertUpdateOp(
				for: local.localID,
				serverID: local.serverID,
				entityType: .receipt,
				payloadDict: [
					"totalAmount": totalAmount,
					"purchasedBy": purchasedBy,
					"notes": notes,
				]
			)
		}
		return local.toReceipt()
	}

	func enqueueReceiptDelete(receiptID: String) {
		guard let local = findLocalReceipt(byModelID: receiptID) else { return }
		enqueueDelete(for: local, entityType: .receipt)
	}

	// MARK: - Merge (online fetch → upsert into SwiftData → return refreshed array)

	@discardableResult
	func mergeGroceries(_ serverItems: [GroceryItem]) -> [GroceryItem] {
		mergeServerItems(
			serverItems,
			findLocal: { self.findLocalGroceryItem(byServerID: $0.id) },
			insertLocal: { item in
				LocalGroceryItem(
					serverID: item.id,
					syncStatus: .synced,
					name: item.name,
					category: item.category,
					isNeeded: item.isNeeded,
					isShoppingChecked: item.isShoppingChecked
				)
			},
			applyServerValues: { local, item in local.applyServerValues(item) },
			serverID: { $0.serverID },
			syncStatus: { $0.syncStatus },
			loadMerged: loadAllGroceryItems
		)
	}

	@discardableResult
	func mergeMealPlans(_ serverPlans: [MealPlan]) -> [MealPlan] {
		mergeServerItems(
			serverPlans,
			findLocal: { self.findLocalMealPlan(byServerID: $0.id) },
			insertLocal: { plan in
				LocalMealPlan(
					serverID: plan.id,
					syncStatus: .synced,
					date: plan.date,
					mealDescription: plan.mealDescription
				)
			},
			applyServerValues: { local, plan in local.applyServerValues(plan) },
			serverID: { $0.serverID },
			syncStatus: { $0.syncStatus },
			loadMerged: loadAllMealPlans
		)
	}

	@discardableResult
	func mergeReceipts(_ serverReceipts: [Receipt]) -> [Receipt] {
		mergeServerItems(
			serverReceipts,
			findLocal: { self.findLocalReceipt(byServerID: $0.id) },
			insertLocal: { receipt in
				LocalReceipt(
					serverID: receipt.id,
					syncStatus: .synced,
					date: receipt.date,
					totalAmount: receipt.totalAmount,
					purchasedBy: receipt.purchasedBy,
					items: receipt.items,
					notes: receipt.notes
				)
			},
			applyServerValues: { local, receipt in local.applyServerValues(receipt) },
			serverID: { $0.serverID },
			syncStatus: { $0.syncStatus },
			loadMerged: loadAllReceipts
		)
	}

	// MARK: - Load All (offline read path)

	func loadAllGroceryItems() -> [GroceryItem] {
		loadAll(LocalGroceryItem.self)
			.filter { $0.syncStatus != .pendingDelete }
			.map { $0.toGroceryItem() }
	}

	func loadAllMealPlans() -> [MealPlan] {
		loadAll(LocalMealPlan.self)
			.filter { $0.syncStatus != .pendingDelete }
			.map { $0.toMealPlan() }
	}

	func loadAllReceipts() -> [Receipt] {
		loadAll(LocalReceipt.self)
			.filter { $0.syncStatus != .pendingDelete }
			.map { $0.toReceipt() }
	}

	// MARK: - WebSocket Filter

	/// True when there is at least one pending SyncOperation for the given server ID.
	/// Used by SocketService to skip incoming events for locally-dirty entities.
	func hasPendingOperation(serverID: String) -> Bool {
		guard let context = modelContext else { return false }
		let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
		return all.contains { $0.serverID == serverID }
	}

	// MARK: - Logout Cleanup

	func clearLocalData() {
		guard let context = modelContext else { return }
		try? context.delete(model: LocalGroceryItem.self)
		try? context.delete(model: LocalMealPlan.self)
		try? context.delete(model: LocalReceipt.self)
		try? context.delete(model: SyncOperation.self)
		try? context.save()
		log("Local store cleared")
	}

	// MARK: - Private Helpers

	private func mergeServerItems<Server, Local: PersistentModel, Output>(
		_ serverItems: [Server],
		findLocal: (Server) -> Local?,
		insertLocal: (Server) -> Local,
		applyServerValues: (Local, Server) -> Void,
		serverID: (Local) -> String?,
		syncStatus: (Local) -> SyncStatus,
		loadMerged: () -> [Output]
	) -> [Output] where Server: Identifiable, Server.ID == String {
		guard let context = modelContext else { return serverItems as? [Output] ?? [] }
		let serverIDs = Set(serverItems.map(\.id))

		for item in serverItems {
			if let local = findLocal(item) {
				if syncStatus(local) == .synced {
					applyServerValues(local, item)
				}
			} else {
				context.insert(insertLocal(item))
			}
		}

		for local in loadAll(Local.self) {
			guard let id = serverID(local) else { continue }
			guard syncStatus(local) == .synced else { continue }
			if !serverIDs.contains(id) {
				context.delete(local)
			}
		}

		try? context.save()
		return loadMerged()
	}

	/// Inserts a local entity and its create SyncOperation, then persists and flushes.
	private func insertCreate<T: Encodable>(
		_ local: some PersistentModel,
		entityType: SyncEntityType,
		localID: UUID,
		encodable: T
	) {
		guard let context = modelContext else { return }
		context.insert(local)
		let payload = (try? JSONEncoder().encode(encodable)) ?? Data()
		context.insert(
			SyncOperation(
				entityType: entityType,
				operationType: .create,
				payload: payload,
				localID: localID
			))
		persist()
	}

	/// Creates or replaces the pending update op for a given local entity.
	/// Replacing prevents queue bloat when the user edits an entity multiple times offline.
	private func upsertUpdateOp(
		for localID: UUID,
		serverID: String?,
		entityType: SyncEntityType,
		payloadDict: [String: Any]
	) {
		guard let context = modelContext else { return }
		let payloadData: Data
		switch entityType {
		case .grocery:
			let payload = GroceryPatchPayload(
				isNeeded: payloadDict["isNeeded"] as? Bool ?? true,
				isShoppingChecked: payloadDict["isShoppingChecked"] as? Bool ?? false
			)
			payloadData = (try? JSONEncoder().encode(payload)) ?? Data()
		case .meal:
			let payload = MealPatchPayload(
				mealDescription: payloadDict["mealDescription"] as? String ?? ""
			)
			payloadData = (try? JSONEncoder().encode(payload)) ?? Data()
		case .receipt:
			let payload = ReceiptPatchPayload(
				totalAmount: payloadDict["totalAmount"] as? Double ?? 0,
				purchasedBy: payloadDict["purchasedBy"] as? String ?? "",
				notes: payloadDict["notes"] as? String
			)
			payloadData = (try? JSONEncoder().encode(payload)) ?? Data()
		}

		// Fetch all ops for this entity and filter in memory to avoid predicating
		// on the SyncOperationType enum property, which SwiftData stores as Codable.
		let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
		let existing = all.first { $0.localID == localID && $0.operationType == .update }

		if let op = existing {
			op.payload = payloadData
			op.retryCount = 0
			op.lastError = nil
		} else {
			context.insert(
				SyncOperation(
					entityType: entityType,
					operationType: .update,
					payload: payloadData,
					localID: localID,
					serverID: serverID
				))
		}
		persist()
	}

	private func enqueueDelete(for local: LocalGroceryItem, entityType: SyncEntityType) {
		enqueueDelete(
			localID: local.localID,
			serverID: local.serverID,
			syncStatus: local.syncStatus,
			deleteLocal: { context in context.delete(local) },
			markPendingDelete: { local.syncStatus = .pendingDelete },
			entityType: entityType
		)
	}

	private func enqueueDelete(for local: LocalMealPlan, entityType: SyncEntityType) {
		enqueueDelete(
			localID: local.localID,
			serverID: local.serverID,
			syncStatus: local.syncStatus,
			deleteLocal: { context in context.delete(local) },
			markPendingDelete: { local.syncStatus = .pendingDelete },
			entityType: entityType
		)
	}

	private func enqueueDelete(for local: LocalReceipt, entityType: SyncEntityType) {
		enqueueDelete(
			localID: local.localID,
			serverID: local.serverID,
			syncStatus: local.syncStatus,
			deleteLocal: { context in context.delete(local) },
			markPendingDelete: { local.syncStatus = .pendingDelete },
			entityType: entityType
		)
	}

	private func enqueueDelete(
		localID: UUID,
		serverID: String?,
		syncStatus: SyncStatus,
		deleteLocal: (ModelContext) -> Void,
		markPendingDelete: () -> Void,
		entityType: SyncEntityType
	) {
		guard let context = modelContext else { return }

		if syncStatus == .pendingCreate {
			cancelOps(for: localID)
			deleteLocal(context)
		} else {
			cancelOps(for: localID)
			markPendingDelete()
			context.insert(
				SyncOperation(
					entityType: entityType,
					operationType: .delete,
					payload: Data(),
					localID: localID,
					serverID: serverID
				))
		}
		persist()
	}

	/// Deletes all SyncOperations for a given localID (used when purging a pending-create entity).
	private func cancelOps(for localID: UUID) {
		guard let context = modelContext else { return }
		let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
		all.filter { $0.localID == localID }.forEach { context.delete($0) }
	}

	private func fetchOps(for localID: UUID, after date: Date) -> [SyncOperation] {
		guard let context = modelContext else { return [] }
		let all =
			(try? context.fetch(
				FetchDescriptor<SyncOperation>(
					sortBy: [SortDescriptor(\.createdAt)]
				))) ?? []
		return all.filter { $0.localID == localID && $0.createdAt > date }
	}

	private func markSynced(entityType: SyncEntityType, serverID: String) {
		switch entityType {
		case .grocery: findLocalGroceryItem(byServerID: serverID)?.syncStatus = .synced
		case .meal: findLocalMealPlan(byServerID: serverID)?.syncStatus = .synced
		case .receipt: findLocalReceipt(byServerID: serverID)?.syncStatus = .synced
		}
	}

	private func deleteLocalEntity(entityType: SyncEntityType, localID: UUID) {
		guard let context = modelContext else { return }
		switch entityType {
		case .grocery: findLocalGroceryItem(byLocalID: localID).map { context.delete($0) }
		case .meal: findLocalMealPlan(byLocalID: localID).map { context.delete($0) }
		case .receipt: findLocalReceipt(byLocalID: localID).map { context.delete($0) }
		}
	}

	/// Saves to SwiftData and immediately attempts a sync if online.
	private func persist() {
		try? modelContext?.save()
		syncIfNeeded()
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

	// MARK: - Lookups

	private func findLocalGroceryItem(byLocalID id: UUID) -> LocalGroceryItem? {
		fetchFirst(FetchDescriptor<LocalGroceryItem>(predicate: #Predicate { $0.localID == id }))
	}

	private func findLocalGroceryItem(byServerID id: String) -> LocalGroceryItem? {
		let sid: String? = id
		return fetchFirst(
			FetchDescriptor<LocalGroceryItem>(predicate: #Predicate { $0.serverID == sid })
		)
	}

	private func findLocalGroceryItem(byModelID id: String) -> LocalGroceryItem? {
		findLocalGroceryItem(byServerID: id)
			?? UUID(uuidString: id).flatMap { findLocalGroceryItem(byLocalID: $0) }
	}

	private func findLocalMealPlan(byLocalID id: UUID) -> LocalMealPlan? {
		fetchFirst(FetchDescriptor<LocalMealPlan>(predicate: #Predicate { $0.localID == id }))
	}

	private func findLocalMealPlan(byServerID id: String) -> LocalMealPlan? {
		let sid: String? = id
		return fetchFirst(
			FetchDescriptor<LocalMealPlan>(predicate: #Predicate { $0.serverID == sid })
		)
	}

	private func findLocalMealPlan(byModelID id: String) -> LocalMealPlan? {
		findLocalMealPlan(byServerID: id)
			?? UUID(uuidString: id).flatMap { findLocalMealPlan(byLocalID: $0) }
	}

	private func findLocalReceipt(byLocalID id: UUID) -> LocalReceipt? {
		fetchFirst(FetchDescriptor<LocalReceipt>(predicate: #Predicate { $0.localID == id }))
	}

	private func findLocalReceipt(byServerID id: String) -> LocalReceipt? {
		let sid: String? = id
		return fetchFirst(
			FetchDescriptor<LocalReceipt>(predicate: #Predicate { $0.serverID == sid })
		)
	}

	private func findLocalReceipt(byModelID id: String) -> LocalReceipt? {
		findLocalReceipt(byServerID: id)
			?? UUID(uuidString: id).flatMap { findLocalReceipt(byLocalID: $0) }
	}

	private func loadAll<T: PersistentModel>(_ type: T.Type) -> [T] {
		guard let context = modelContext else { return [] }
		return (try? context.fetch(FetchDescriptor<T>())) ?? []
	}

	private func fetchFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> T? {
		guard let context = modelContext else { return nil }
		return try? context.fetch(descriptor).first
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
