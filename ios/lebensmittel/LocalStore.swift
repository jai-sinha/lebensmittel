//
//  LocalStore.swift
//  lebensmittel
//
//  Created by Jai Sinha on 3/25/26.
//

import Foundation
import SwiftData

// MARK: - Sync Enums

enum SyncStatus: Int, Codable {
	case synced = 0
	case pendingCreate = 1
	case pendingUpdate = 2
	case pendingDelete = 3
}

enum SyncEntityType: String, Codable {
	case grocery = "grocery"
	case meal = "meal"
	case receipt = "receipt"
}

// MARK: - Group Persistence

@Model
final class LocalGroupState {
	@Attribute(.unique) var id: String
	var activeGroupID: String?
	var knownGroupsData: Data
	var legacyGroupMigrationCompleted: Bool

	init(
		id: String = "group-state",
		activeGroupID: String? = nil,
		knownGroupsData: Data = Data(),
		legacyGroupMigrationCompleted: Bool = false
	) {
		self.id = id
		self.activeGroupID = activeGroupID
		self.knownGroupsData = knownGroupsData
		self.legacyGroupMigrationCompleted = legacyGroupMigrationCompleted
	}

	static let singletonID = "group-state"
}

@MainActor
final class GroupStore {
	static let shared = GroupStore()

	private var modelContext: ModelContext?
	var legacyGroupMigrationCompleted = false

	func configure(modelContext: ModelContext) {
		self.modelContext = modelContext
	}

	func loadSnapshot() -> GroupSnapshotData {
		guard let state = fetchState() else {
			return GroupSnapshotData()
		}

		legacyGroupMigrationCompleted = state.legacyGroupMigrationCompleted
		return GroupSnapshotData(
			activeGroupId: state.activeGroupID?.trimmedNilIfEmpty,
			knownGroups: decodeKnownGroups(from: state.knownGroupsData),
			legacyGroupMigrationCompleted: state.legacyGroupMigrationCompleted
		)
	}

	func save(
		activeGroupId: String?,
		knownGroups: [AuthGroup],
		legacyGroupMigrationCompleted: Bool
	) {
		guard let state = fetchOrCreateState() else { return }
		state.activeGroupID = activeGroupId
		state.knownGroupsData = encodeKnownGroups(knownGroups)
		state.legacyGroupMigrationCompleted = legacyGroupMigrationCompleted

		try? modelContext?.save()
	}

	private func fetchState() -> LocalGroupState? {
		guard let modelContext else { return nil }
		let descriptor = FetchDescriptor<LocalGroupState>()
		return try? modelContext.fetch(descriptor).first(where: { $0.id == LocalGroupState.singletonID })
	}

	private func fetchOrCreateState() -> LocalGroupState? {
		if let existing = fetchState() {
			return existing
		}

		guard let modelContext else { return nil }
		let state = LocalGroupState()
		modelContext.insert(state)
		return state
	}

	private func decodeKnownGroups(from data: Data) -> [AuthGroup] {
		guard !data.isEmpty,
			let groups = try? JSONDecoder().decode([AuthGroup].self, from: data)
		else {
			return []
		}
		return sortGroups(groups)
	}

	private func encodeKnownGroups(_ groups: [AuthGroup]) -> Data {
		(try? JSONEncoder().encode(sortGroups(groups))) ?? Data()
	}

	private func sortGroups(_ groups: [AuthGroup]) -> [AuthGroup] {
		groups.sorted { lhs, rhs in
			lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
		}
	}
}

struct GroupSnapshotData {
	var activeGroupId: String? = nil
	var knownGroups: [AuthGroup] = []
	var legacyGroupMigrationCompleted: Bool = false
}

extension String {
	var trimmedNilIfEmpty: String? {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}

enum SyncOperationType: String, Codable {
	case create = "create"
	case update = "update"
	case delete = "delete"
}

// MARK: - Local Entity Models

@Model
final class LocalGroceryItem {
	@Attribute(.unique) var localID: UUID
	var syncStatus: SyncStatus

	var name: String
	var category: String
	var isNeeded: Bool
	var isShoppingChecked: Bool

	init(
		localID: UUID = UUID(),
		syncStatus: SyncStatus = .pendingCreate,
		name: String,
		category: String,
		isNeeded: Bool = true,
		isShoppingChecked: Bool = false
	) {
		self.localID = localID
		self.syncStatus = syncStatus
		self.name = name
		self.category = category
		self.isNeeded = isNeeded
		self.isShoppingChecked = isShoppingChecked
	}

	/// Converts to the shared GroceryItem DTO used by views.
	func toGroceryItem() -> GroceryItem {
		GroceryItem(
			id: localID.uuidString,
			name: name,
			category: category,
			isNeeded: isNeeded,
			isShoppingChecked: isShoppingChecked
		)
	}

	/// Overwrites mutable fields from a server-fetched GroceryItem and marks as synced.
	func applyServerValues(_ item: GroceryItem) {
		name = item.name
		category = item.category
		isNeeded = item.isNeeded
		isShoppingChecked = item.isShoppingChecked
		syncStatus = .synced
	}
}

// MARK: -

@Model
final class LocalMealPlan {
	@Attribute(.unique) var localID: UUID
	var syncStatus: SyncStatus

	/// Stored as "yyyy-MM-dd", matching the server wire format.
	var date: String
	var mealDescription: String

	init(
		localID: UUID = UUID(),
		syncStatus: SyncStatus = .pendingCreate,
		date: String,
		mealDescription: String
	) {
		self.localID = localID
		self.syncStatus = syncStatus
		self.date = date
		self.mealDescription = mealDescription
	}

	/// Converts to the shared MealPlan DTO used by views.
	func toMealPlan() -> MealPlan {
		MealPlan(
			id: localID.uuidString,
			date: date,
			mealDescription: mealDescription
		)
	}

	/// Overwrites mutable fields from a server-fetched MealPlan and marks as synced.
	func applyServerValues(_ plan: MealPlan) {
		date = plan.date
		mealDescription = plan.mealDescription
		syncStatus = .synced
	}
}

// MARK: -

@Model
final class LocalReceipt {
	@Attribute(.unique) var localID: UUID
	var syncStatus: SyncStatus

	/// Stored as "yyyy-MM-dd", matching the server wire format.
	var date: String
	var totalAmount: Double
	var purchasedBy: String
	var items: [String]
	var notes: String?

	init(
		localID: UUID = UUID(),
		syncStatus: SyncStatus = .pendingCreate,
		date: String,
		totalAmount: Double,
		purchasedBy: String,
		items: [String] = [],
		notes: String? = nil
	) {
		self.localID = localID
		self.syncStatus = syncStatus
		self.date = date
		self.totalAmount = totalAmount
		self.purchasedBy = purchasedBy
		self.items = items
		self.notes = notes
	}

	/// Converts to the shared Receipt DTO used by views.
	func toReceipt() -> Receipt {
		Receipt(
			id: localID.uuidString,
			date: date,
			totalAmount: totalAmount,
			purchasedBy: purchasedBy,
			items: items,
			notes: notes
		)
	}

	/// Overwrites mutable fields from a server-fetched Receipt and marks as synced.
	func applyServerValues(_ receipt: Receipt) {
		date = receipt.date
		totalAmount = receipt.totalAmount
		purchasedBy = receipt.purchasedBy
		items = receipt.items
		notes = receipt.notes
		syncStatus = .synced
	}
}

// MARK: - Sync Operation Queue

@Model
final class SyncOperation {
	@Attribute(.unique) var id: UUID
	var entityType: SyncEntityType
	var operationType: SyncOperationType
	/// JSON-encoded request body to replay against the server.
	var payload: Data
	/// References the LocalXxx entity that owns this operation.
	var localID: UUID
	var createdAt: Date
	var retryCount: Int
	var lastError: String?

	init(
		id: UUID = UUID(),
		entityType: SyncEntityType,
		operationType: SyncOperationType,
		payload: Data,
		localID: UUID,
		createdAt: Date = Date(),
		retryCount: Int = 0,
		lastError: String? = nil
	) {
		self.id = id
		self.entityType = entityType
		self.operationType = operationType
		self.payload = payload
		self.localID = localID
		self.createdAt = createdAt
		self.retryCount = retryCount
		self.lastError = lastError
	}
}

// MARK: - Generic Entity Store

/// Common lifecycle contract for a local SwiftData entity and its wire DTO.
/// Conformance lives in extensions below, so each model keeps its own fields.
protocol LocalEntity: PersistentModel {
	associatedtype DTO: Codable & Identifiable where DTO.ID == String
	var localID: UUID { get set }
	var syncStatus: SyncStatus { get set }
	func toDTO() -> DTO
	func applyServerValues(_ dto: DTO)
	static func make(from dto: DTO, syncStatus: SyncStatus) -> Self?
}

extension LocalGroceryItem: LocalEntity {
	func toDTO() -> GroceryItem { toGroceryItem() }

	static func make(from dto: GroceryItem, syncStatus: SyncStatus) -> LocalGroceryItem? {
		guard let localID = UUID(uuidString: dto.id) else { return nil }
		return LocalGroceryItem(
			localID: localID,
			syncStatus: syncStatus,
			name: dto.name,
			category: dto.category,
			isNeeded: dto.isNeeded,
			isShoppingChecked: dto.isShoppingChecked
		)
	}
}

extension LocalMealPlan: LocalEntity {
	func toDTO() -> MealPlan { toMealPlan() }

	static func make(from dto: MealPlan, syncStatus: SyncStatus) -> LocalMealPlan? {
		guard let localID = UUID(uuidString: dto.id) else { return nil }
		return LocalMealPlan(
			localID: localID,
			syncStatus: syncStatus,
			date: dto.date,
			mealDescription: dto.mealDescription
		)
	}
}

extension LocalReceipt: LocalEntity {
	func toDTO() -> Receipt { toReceipt() }

	static func make(from dto: Receipt, syncStatus: SyncStatus) -> LocalReceipt? {
		guard let localID = UUID(uuidString: dto.id) else { return nil }
		return LocalReceipt(
			localID: localID,
			syncStatus: syncStatus,
			date: dto.date,
			totalAmount: dto.totalAmount,
			purchasedBy: dto.purchasedBy,
			items: dto.items,
			notes: dto.notes
		)
	}
}

/// One generic entity store: owns all SwiftData writes, the durable operation
/// queue, and outbound sync for a single entity type. The three concrete
/// instances (grocery / meal / receipt) differ only in configuration.
@MainActor
final class EntityStore<DTO, Local>
where DTO: Codable & Identifiable, DTO.ID == String, Local: LocalEntity, Local.DTO == DTO {

	private let entityType: SyncEntityType
	private let modelContext: ModelContext
	private let makeCreatePayload: (Local) -> Data
	private let createRemote: (Data) async throws -> DTO
	private let updateRemote: (String, Data) async throws -> Void
	private let deleteRemote: (String) async throws -> Void
	private let onMutate: () -> Void

	init(
		entityType: SyncEntityType,
		modelContext: ModelContext,
		makeCreatePayload: @escaping (Local) -> Data,
		createRemote: @escaping (Data) async throws -> DTO,
		updateRemote: @escaping (String, Data) async throws -> Void,
		deleteRemote: @escaping (String) async throws -> Void,
		onMutate: @escaping () -> Void
	) {
		self.entityType = entityType
		self.modelContext = modelContext
		self.makeCreatePayload = makeCreatePayload
		self.createRemote = createRemote
		self.updateRemote = updateRemote
		self.deleteRemote = deleteRemote
		self.onMutate = onMutate
	}

	// MARK: - Enqueue

	@discardableResult
	func enqueueCreate(local: Local) -> DTO {
		modelContext.insert(local)
		modelContext.insert(
			SyncOperation(
				entityType: entityType,
				operationType: .create,
				payload: makeCreatePayload(local),
				localID: local.localID
			))
		persist()
		return local.toDTO()
	}

	@discardableResult
	func enqueueUpdate(id: String, mutate: (Local) -> Void, patch: Data) -> DTO? {
		guard let uuid = UUID(uuidString: id), let local = find(localID: uuid) else { return nil }
		mutate(local)
		if local.syncStatus == .pendingCreate {
			// Pending-create: just update local fields. processCreate regenerates
			// the payload from the current entity state at sync time.
			try? modelContext.save()
		} else {
			local.syncStatus = .pendingUpdate
			upsertUpdateOp(for: local.localID, patch: patch)
		}
		return local.toDTO()
	}

	func enqueueDelete(id: String) {
		guard let uuid = UUID(uuidString: id), let local = find(localID: uuid) else { return }
		if local.syncStatus == .pendingCreate {
			cancelOps(for: local.localID)
			modelContext.delete(local)
		} else {
			cancelOps(for: local.localID)
			local.syncStatus = .pendingDelete
			modelContext.insert(
				SyncOperation(
					entityType: entityType,
					operationType: .delete,
					payload: Data(),
					localID: local.localID
				))
		}
		persist()
	}

	// MARK: - Operation Processing

	func process(_ op: SyncOperation) async throws {
		switch op.operationType {
		case .create: try await processCreate(op)
		case .update: try await processUpdate(op)
		case .delete: try await processDelete(op)
		}
	}

	private func processCreate(_ op: SyncOperation) async throws {
		let local = find(localID: op.localID)
		// Rebuild the payload from current local state so offline edits made
		// while pending are reflected; fall back to the stored payload.
		let payload = local.map(makeCreatePayload) ?? op.payload
		let created = try await createRemote(payload)
		if let local {
			local.applyServerValues(created)
			try? modelContext.save()
		}
	}

	private func processUpdate(_ op: SyncOperation) async throws {
		try await updateRemote(op.localID.uuidString, op.payload)
		find(localID: op.localID)?.syncStatus = .synced
		try? modelContext.save()
	}

	private func processDelete(_ op: SyncOperation) async throws {
		try await deleteRemote(op.localID.uuidString)
		find(localID: op.localID).map { modelContext.delete($0) }
		try? modelContext.save()
	}

	// MARK: - Merge (online fetch → upsert into SwiftData → return refreshed array)

	@discardableResult
	func merge(_ items: [DTO]) -> [DTO] {
		let serverUUIDs = Set(items.compactMap { UUID(uuidString: $0.id) })

		for item in items {
			guard let localID = UUID(uuidString: item.id) else { continue }
			if let local = find(localID: localID) {
				if local.syncStatus == .synced {
					local.applyServerValues(item)
				}
			} else if let made = Local.make(from: item, syncStatus: .synced) {
				modelContext.insert(made)
			}
		}

		for local in loadAllLocal() {
			guard local.syncStatus == .synced else { continue }
			if !serverUUIDs.contains(local.localID) {
				modelContext.delete(local)
			}
		}

		try? modelContext.save()
		return loadAll()
	}

	// MARK: - Single-Item Upsert (WebSocket)

	func upsert(_ dto: DTO) {
		guard let localID = UUID(uuidString: dto.id) else { return }
		if let local = find(localID: localID) {
			if local.syncStatus == .synced {
				local.applyServerValues(dto)
			}
		} else if let made = Local.make(from: dto, syncStatus: .synced) {
			modelContext.insert(made)
		}
		try? modelContext.save()
	}

	func deleteSynced(id: String) {
		guard let uuid = UUID(uuidString: id) else { return }
		find(localID: uuid).map { modelContext.delete($0) }
		try? modelContext.save()
	}

	// MARK: - Load All (offline read path)

	func loadAll() -> [DTO] {
		loadAllLocal()
			.filter { $0.syncStatus != .pendingDelete }
			.map { $0.toDTO() }
	}

	// MARK: - Lookups

	func find(localID: UUID) -> Local? {
		loadAllLocal().first { $0.localID == localID }
	}

	private func loadAllLocal() -> [Local] {
		(try? modelContext.fetch(FetchDescriptor<Local>())) ?? []
	}

	// MARK: - Private Helpers

	/// Creates or replaces the pending update op for a given local entity.
	/// Replacing prevents queue bloat when the user edits an entity multiple times offline.
	private func upsertUpdateOp(for localID: UUID, patch: Data) {
		// Fetch all ops and filter in memory to avoid predicating on the
		// SyncOperationType enum property, which SwiftData stores as Codable.
		let all = (try? modelContext.fetch(FetchDescriptor<SyncOperation>())) ?? []
		let existing = all.first { $0.localID == localID && $0.operationType == .update }

		if let op = existing {
			op.payload = patch
			op.retryCount = 0
			op.lastError = nil
		} else {
			modelContext.insert(
				SyncOperation(
					entityType: entityType,
					operationType: .update,
					payload: patch,
					localID: localID
				))
		}
		persist()
	}

	/// Deletes all SyncOperations for a given localID (used when purging a pending-create entity).
	private func cancelOps(for localID: UUID) {
		let all = (try? modelContext.fetch(FetchDescriptor<SyncOperation>())) ?? []
		all.filter { $0.localID == localID }.forEach { modelContext.delete($0) }
	}

	/// Saves to SwiftData and immediately attempts a sync if online.
	private func persist() {
		try? modelContext.save()
		onMutate()
	}
}
