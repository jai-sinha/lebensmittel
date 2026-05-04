//
//  SyncEngine.swift
//  lebensmittel
//
//  Created by Jai Sinha on 3/25/26.
//

import Foundation
import SwiftData

// MARK: - Notification Name

extension Notification.Name {
	static let syncEngineDidFinish = Notification.Name("syncEngineDidFinish")
}

// MARK: - SyncEngine

/// Owns all writes to SwiftData and all outbound network sync.
/// Feature models call the enqueueXxx methods; SyncEngine handles persistence,
/// the durable operation queue, conflict resolution, ID remapping, and retries.
///

@MainActor
final class SyncEngine {
	enum SyncBannerState: Equatable {
		case idle
		case syncing
	}

	static let shared = SyncEngine()

	/// Set to true to enable verbose logging — mirrors SocketService.verbose.
	@MainActor static var verbose = false

	private var modelContext: ModelContext?
	private var groceriesService: (any GroceriesServicing)?
	private var mealsService: (any MealsServicing)?
	private var receiptsService: (any ReceiptsServicing)?
	private var isSyncing = false
	var bannerState: SyncBannerState { isSyncing ? .syncing : .idle }

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
		isSyncing = true
		defer { isSyncing = false }

		let descriptor = FetchDescriptor<SyncOperation>(
			sortBy: [SortDescriptor(\.createdAt, order: .forward)]
		)
		guard let ops = try? context.fetch(descriptor) else {
			log("Failed to fetch pending operations")
			return
		}
		guard !ops.isEmpty else {
			log("Queue empty")
			postFinished()
			return
		}

		log("Processing \(ops.count) operation(s)")

		for op in ops {
			if op.retryCount >= 3 {
				log("Operation \(op.id) hit max retries — discarding")
				context.delete(op)
				try? context.save()
				continue
			}

			do {
				try await process(op)
				context.delete(op)
				try? context.save()
				log("✓ \(op.entityType.rawValue) \(op.operationType.rawValue) \(op.id)")
			} catch {
				op.retryCount += 1
				op.lastError = error.localizedDescription
				try? context.save()
				log(
					"✗ \(op.entityType.rawValue) \(op.operationType.rawValue) — \(error.localizedDescription). Retry \(op.retryCount)/3. Stopping."
				)
				return
			}
		}

		postFinished()
	}

	private func postFinished() {
		log("Sync complete — posting syncEngineDidFinish")
		NotificationCenter.default.post(name: .syncEngineDidFinish, object: nil)
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

		let currentData: Data?
		switch op.entityType {
		case .grocery:
			guard let groceriesService else { throw SyncError.notConfigured }
			guard
				let item = try await groceriesService.fetchGroceries().first(where: {
					$0.id == serverID
				})
			else {
				currentData = nil
				break
			}
			currentData = try JSONEncoder().encode(item)

		case .meal:
			guard let mealsService else { throw SyncError.notConfigured }
			guard
				let plan = try await mealsService.fetchMealPlans().first(where: {
					$0.id == serverID
				})
			else {
				currentData = nil
				break
			}
			currentData = try JSONEncoder().encode(plan)

		case .receipt:
			guard let receiptsService else { throw SyncError.notConfigured }
			guard
				let receipt = try await receiptsService.fetchReceipts().first(where: {
					$0.id == serverID
				})
			else {
				currentData = nil
				break
			}
			currentData = try JSONEncoder().encode(receipt)
		}

		guard let currentData else {
			log(
				"Update target \(op.entityType.rawValue)/\(serverID) no longer exists on server — discarding local change (server wins)"
			)
			deleteLocalEntity(entityType: op.entityType, localID: op.localID)
			try? context.save()
			return
		}

		if let snapshot = op.baseSnapshot,
			(try? hasConflict(
				entityType: op.entityType, serverData: currentData, snapshot: snapshot)) == true
		{
			log(
				"Conflict on \(op.entityType.rawValue)/\(serverID) — discarding local change (server wins)"
			)
			applyServerState(currentData, entityType: op.entityType, serverID: serverID)
			try? context.save()
			return
		}

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

	// MARK: - Conflict Detection

	private func hasConflict(
		entityType: SyncEntityType,
		serverData: Data,
		snapshot: Data
	) throws -> Bool {
		switch entityType {
		case .grocery:
			let s = try JSONDecoder().decode(GroceryItem.self, from: serverData)
			let b = try JSONDecoder().decode(GroceryItem.self, from: snapshot)
			return s.name != b.name
				|| s.category != b.category
				|| s.isNeeded != b.isNeeded
				|| s.isShoppingChecked != b.isShoppingChecked
		case .meal:
			let s = try JSONDecoder().decode(MealPlan.self, from: serverData)
			let b = try JSONDecoder().decode(MealPlan.self, from: snapshot)
			return s.mealDescription != b.mealDescription
		case .receipt:
			let s = try JSONDecoder().decode(Receipt.self, from: serverData)
			let b = try JSONDecoder().decode(Receipt.self, from: snapshot)
			return s.totalAmount != b.totalAmount
				|| s.purchasedBy != b.purchasedBy
				|| s.notes != b.notes
		}
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
		isShoppingChecked: Bool,
		snapshot: GroceryItem
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
				payloadDict: ["isNeeded": isNeeded, "isShoppingChecked": isShoppingChecked],
				snapshot: snapshot
			)
		}
		return local.toGroceryItem()
	}

	func enqueueGroceryDelete(itemID: String) {
		guard let local = findLocalGroceryItem(byModelID: itemID),
			let context = modelContext
		else { return }

		if local.syncStatus == .pendingCreate {
			cancelOps(for: local.localID)
			context.delete(local)
		} else {
			local.syncStatus = .pendingDelete
			context.insert(
				SyncOperation(
					entityType: .grocery,
					operationType: .delete,
					payload: Data(),
					localID: local.localID,
					serverID: local.serverID
				))
		}
		persist()
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
		mealDescription: String,
		snapshot: MealPlan
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
				payloadDict: ["mealDescription": mealDescription],
				snapshot: snapshot
			)
		}
		return local.toMealPlan()
	}

	func enqueueMealDelete(mealID: String) {
		guard let local = findLocalMealPlan(byModelID: mealID),
			let context = modelContext
		else { return }

		if local.syncStatus == .pendingCreate {
			cancelOps(for: local.localID)
			context.delete(local)
		} else {
			local.syncStatus = .pendingDelete
			context.insert(
				SyncOperation(
					entityType: .meal,
					operationType: .delete,
					payload: Data(),
					localID: local.localID,
					serverID: local.serverID
				))
		}
		persist()
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

		// Reset grocery flags locally. No separate PATCH is enqueued because the
		// receipt-create payload carries the items list and the server resets the
		// flags atomically in the same transaction.
		for item in checkedItems {
			findLocalGroceryItem(byModelID: item.id).map {
				$0.isNeeded = false
				$0.isShoppingChecked = false
				if $0.syncStatus == .synced {
					$0.syncStatus = .pendingUpdate
				}
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
		notes: String,
		snapshot: Receipt
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
				],
				snapshot: snapshot
			)
		}
		return local.toReceipt()
	}

	func enqueueReceiptDelete(receiptID: String) {
		guard let local = findLocalReceipt(byModelID: receiptID),
			let context = modelContext
		else { return }

		if local.syncStatus == .pendingCreate {
			cancelOps(for: local.localID)
			context.delete(local)
		} else {
			local.syncStatus = .pendingDelete
			context.insert(
				SyncOperation(
					entityType: .receipt,
					operationType: .delete,
					payload: Data(),
					localID: local.localID,
					serverID: local.serverID
				))
		}
		persist()
	}

	// MARK: - Merge (online fetch → upsert into SwiftData → return refreshed array)

	@discardableResult
	func mergeGroceries(_ serverItems: [GroceryItem]) -> [GroceryItem] {
		guard let context = modelContext else { return serverItems }
		for item in serverItems {
			if let local = findLocalGroceryItem(byServerID: item.id) {
				if local.syncStatus == .synced { local.applyServerValues(item) }
				// else: pending local change — skip; server wins after next sync
			} else {
				context.insert(
					LocalGroceryItem(
						serverID: item.id, syncStatus: .synced,
						name: item.name, category: item.category,
						isNeeded: item.isNeeded, isShoppingChecked: item.isShoppingChecked
					))
			}
		}
		try? context.save()
		return loadAllGroceryItems()
	}

	@discardableResult
	func mergeMealPlans(_ serverPlans: [MealPlan]) -> [MealPlan] {
		guard let context = modelContext else { return serverPlans }
		for plan in serverPlans {
			if let local = findLocalMealPlan(byServerID: plan.id) {
				if local.syncStatus == .synced { local.applyServerValues(plan) }
			} else {
				context.insert(
					LocalMealPlan(
						serverID: plan.id, syncStatus: .synced,
						date: plan.date, mealDescription: plan.mealDescription
					))
			}
		}
		try? context.save()
		return loadAllMealPlans()
	}

	@discardableResult
	func mergeReceipts(_ serverReceipts: [Receipt]) -> [Receipt] {
		guard let context = modelContext else { return serverReceipts }
		for receipt in serverReceipts {
			if let local = findLocalReceipt(byServerID: receipt.id) {
				if local.syncStatus == .synced { local.applyServerValues(receipt) }
			} else {
				context.insert(
					LocalReceipt(
						serverID: receipt.id, syncStatus: .synced,
						date: receipt.date, totalAmount: receipt.totalAmount,
						purchasedBy: receipt.purchasedBy, items: receipt.items, notes: receipt.notes
					))
			}
		}
		try? context.save()
		return loadAllReceipts()
	}

	// MARK: - Load All (offline read path)

	func loadAllGroceryItems() -> [GroceryItem] {
		guard let context = modelContext else { return [] }
		let all = (try? context.fetch(FetchDescriptor<LocalGroceryItem>())) ?? []
		return all.filter { $0.syncStatus != .pendingDelete }.map { $0.toGroceryItem() }
	}

	func loadAllMealPlans() -> [MealPlan] {
		guard let context = modelContext else { return [] }
		let all = (try? context.fetch(FetchDescriptor<LocalMealPlan>())) ?? []
		return all.filter { $0.syncStatus != .pendingDelete }.map { $0.toMealPlan() }
	}

	func loadAllReceipts() -> [Receipt] {
		guard let context = modelContext else { return [] }
		let all = (try? context.fetch(FetchDescriptor<LocalReceipt>())) ?? []
		return all.filter { $0.syncStatus != .pendingDelete }.map { $0.toReceipt() }
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
		payloadDict: [String: Any],
		snapshot: some Encodable
	) {
		guard let context = modelContext else { return }
		let snapshotData = (try? JSONEncoder().encode(snapshot)) ?? Data()
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
			op.baseSnapshot = snapshotData
			op.retryCount = 0
			op.lastError = nil
		} else {
			context.insert(
				SyncOperation(
					entityType: entityType,
					operationType: .update,
					payload: payloadData,
					baseSnapshot: snapshotData,
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

	private func applyServerState(_ data: Data, entityType: SyncEntityType, serverID: String) {
		switch entityType {
		case .grocery:
			if let item = try? JSONDecoder().decode(GroceryItem.self, from: data) {
				findLocalGroceryItem(byServerID: serverID)?.applyServerValues(item)
			}
		case .meal:
			if let plan = try? JSONDecoder().decode(MealPlan.self, from: data) {
				findLocalMealPlan(byServerID: serverID)?.applyServerValues(plan)
			}
		case .receipt:
			if let receipt = try? JSONDecoder().decode(Receipt.self, from: data) {
				findLocalReceipt(byServerID: serverID)?.applyServerValues(receipt)
			}
		}
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
		guard let ctx = modelContext else { return nil }
		return try? ctx.fetch(
			FetchDescriptor<LocalGroceryItem>(predicate: #Predicate { $0.localID == id })
		).first
	}

	private func findLocalGroceryItem(byServerID id: String) -> LocalGroceryItem? {
		guard let ctx = modelContext else { return nil }
		let sid: String? = id
		return try? ctx.fetch(
			FetchDescriptor<LocalGroceryItem>(predicate: #Predicate { $0.serverID == sid })
		).first
	}

	private func findLocalGroceryItem(byModelID id: String) -> LocalGroceryItem? {
		findLocalGroceryItem(byServerID: id)
			?? UUID(uuidString: id).flatMap { findLocalGroceryItem(byLocalID: $0) }
	}

	private func findLocalMealPlan(byLocalID id: UUID) -> LocalMealPlan? {
		guard let ctx = modelContext else { return nil }
		return try? ctx.fetch(
			FetchDescriptor<LocalMealPlan>(predicate: #Predicate { $0.localID == id })
		).first
	}

	private func findLocalMealPlan(byServerID id: String) -> LocalMealPlan? {
		guard let ctx = modelContext else { return nil }
		let sid: String? = id
		return try? ctx.fetch(
			FetchDescriptor<LocalMealPlan>(predicate: #Predicate { $0.serverID == sid })
		).first
	}

	private func findLocalMealPlan(byModelID id: String) -> LocalMealPlan? {
		findLocalMealPlan(byServerID: id)
			?? UUID(uuidString: id).flatMap { findLocalMealPlan(byLocalID: $0) }
	}

	private func findLocalReceipt(byLocalID id: UUID) -> LocalReceipt? {
		guard let ctx = modelContext else { return nil }
		return try? ctx.fetch(
			FetchDescriptor<LocalReceipt>(predicate: #Predicate { $0.localID == id })
		).first
	}

	private func findLocalReceipt(byServerID id: String) -> LocalReceipt? {
		guard let ctx = modelContext else { return nil }
		let sid: String? = id
		return try? ctx.fetch(
			FetchDescriptor<LocalReceipt>(predicate: #Predicate { $0.serverID == sid })
		).first
	}

	private func findLocalReceipt(byModelID id: String) -> LocalReceipt? {
		findLocalReceipt(byServerID: id)
			?? UUID(uuidString: id).flatMap { findLocalReceipt(byLocalID: $0) }
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
