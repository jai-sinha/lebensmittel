//
//  SyncEngine.swift
//  lebensmittel
//
//  Created by Jai Sinha on 3/25/26.
//

import Foundation
import SwiftData

// MARK: - SyncEngine

/// Feature models call the enqueueXxx methods; SyncEngine handles persistence,
/// the durable operation queue, conflict resolution, ID remapping, and retries.

@MainActor
final class SyncEngine {
	static let shared = SyncEngine()

	@MainActor static var verbose = false

	private var modelContext: ModelContext?

	private var groceryStore: EntityStore<GroceryItem, LocalGroceryItem>?
	private var mealStore: EntityStore<MealPlan, LocalMealPlan>?
	private var receiptStore: EntityStore<Receipt, LocalReceipt>?

	private let groceriesModel = GroceriesModel.shared
	private let mealsModel = MealsModel.shared
	private let receiptsModel = ReceiptsModel.shared
	private let groupModel = GroupModel.shared

	private(set) var isSyncing = false
	private var reconcileTask: Task<Void, Error>?

	private init() {}

	func configure(modelContext: ModelContext) {
		self.modelContext = modelContext

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
				return try await GroceriesService.shared.createGroceryItem(payload)
			},
			updateRemote: { id, data in
				let payload = try JSONDecoder().decode(GroceryPatchPayload.self, from: data)
				try await GroceriesService.shared.updateGroceryItem(
					id: id,
					isNeeded: payload.isNeeded,
					isShoppingChecked: payload.isShoppingChecked,
					category: payload.category,
					name: payload.name
				)
			},
			deleteRemote: { id in
				try await GroceriesService.shared.deleteGroceryItem(id: id)
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
				return try await MealsService.shared.createMealPlan(payload)
			},
			updateRemote: { id, data in
				let payload = try JSONDecoder().decode(MealPatchPayload.self, from: data)
				try await MealsService.shared.updateMealPlan(id: id, mealDescription: payload.mealDescription)
			},
			deleteRemote: { id in
				try await MealsService.shared.deleteMealPlan(id: id)
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
				return try await ReceiptsService.shared.createReceipt(payload)
			},
			updateRemote: { id, data in
				let payload = try JSONDecoder().decode(ReceiptPatchPayload.self, from: data)
				try await ReceiptsService.shared.updateReceipt(
					id: id,
					price: payload.totalAmount,
					purchasedBy: payload.purchasedBy,
					notes: payload.notes ?? ""
				)
			},
			deleteRemote: { id in
				try await ReceiptsService.shared.deleteReceipt(id: id)
			},
			onMutate: onMutate
		)

		log("Configured")
	}

	func syncIfNeeded() {
		guard ConnectivityMonitor.shared.isOnline else {
			log("Offline, skipping")
			return
		}
		Task {
			await drainQueue()
		}
	}

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

	/// replicates the server's receipt-creation transaction locally
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

	/// apply upserts, ignore echoes
	func applyServerUpsert(_ item: GroceryItem) {
		guard groceryStore?.applyServerChange(item) == true else { return }
		groceriesModel.addItem(item)
	}

	func applyServerUpsert(_ plan: MealPlan) {
		guard mealStore?.applyServerChange(plan) == true else { return }
		mealsModel.addMealPlan(plan)
	}

	func applyServerUpsert(_ receipt: Receipt) {
		guard receiptStore?.applyServerChange(receipt) == true else { return }
		receiptsModel.addReceipt(receipt)
	}

	func applyServerDelete(type: SyncEntityType, id: UUID) {
		switch type {
		case .grocery:
			guard groceryStore?.applyServerDelete(id: id) == true else { return }
			groceriesModel.removeItem(withId: id)
		case .meal:
			guard mealStore?.applyServerDelete(id: id) == true else { return }
			mealsModel.removeMealPlan(withId: id)
		case .receipt:
			guard receiptStore?.applyServerDelete(id: id) == true else { return }
			receiptsModel.deleteReceipt(withId: id)
		}
	}

	/// bring the local copy up to date with the server for the active group
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
		let response = try await ChangesService.shared.fetchChanges(
			afterSeq: forceSnapshot ? nil : cursor(for: groupID)
		)

		// make sure the groupid is stable
		guard groupID == groupModel.getActiveGroupId() else { return }

		if response.isFull {
			groceriesModel.replaceAll(
				with: groceryStore?.merge(response.grocery, for: groupID) ?? [])
			mealsModel.replaceAll(with: mealStore?.merge(response.meal, for: groupID) ?? [])
			receiptsModel.replaceAll(
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

	/// loads the active group's local entities from SwiftData.
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

	/// republish the local store into the feature models, for when it changed locally
	func reloadModels() {
		groceriesModel.replaceAll(with: loadAllGroceryItems())
		mealsModel.replaceAll(with: loadAllMealPlans())
		receiptsModel.replaceAll(with: loadAllReceipts())
	}

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
