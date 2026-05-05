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

enum SyncOperationType: String, Codable {
	case create = "create"
	case update = "update"
	case delete = "delete"
}

// MARK: - Local Entity Models

@Model
final class LocalGroceryItem {
	@Attribute(.unique) var localID: UUID
	var serverID: String?
	var syncStatus: SyncStatus

	var name: String
	var category: String
	var isNeeded: Bool
	var isShoppingChecked: Bool

	init(
		localID: UUID = UUID(),
		serverID: String? = nil,
		syncStatus: SyncStatus = .pendingCreate,
		name: String,
		category: String,
		isNeeded: Bool = true,
		isShoppingChecked: Bool = false
	) {
		self.localID = localID
		self.serverID = serverID
		self.syncStatus = syncStatus
		self.name = name
		self.category = category
		self.isNeeded = isNeeded
		self.isShoppingChecked = isShoppingChecked
	}

	/// Converts to the shared GroceryItem DTO used by views.
	/// Pending-create items use localID.uuidString as a temporary id.
	func toGroceryItem() -> GroceryItem {
		GroceryItem(
			id: serverID ?? localID.uuidString,
			name: name,
			category: category,
			isNeeded: isNeeded,
			isShoppingChecked: isShoppingChecked
		)
	}

	/// Overwrites mutable fields from a server-fetched GroceryItem and marks as synced.
	func applyServerValues(_ item: GroceryItem) {
		serverID = item.id
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
	var serverID: String?
	var syncStatus: SyncStatus

	/// Stored as "yyyy-MM-dd", matching the server wire format.
	var date: String
	var mealDescription: String

	init(
		localID: UUID = UUID(),
		serverID: String? = nil,
		syncStatus: SyncStatus = .pendingCreate,
		date: String,
		mealDescription: String
	) {
		self.localID = localID
		self.serverID = serverID
		self.syncStatus = syncStatus
		self.date = date
		self.mealDescription = mealDescription
	}

	/// Converts to the shared MealPlan DTO used by views.
	func toMealPlan() -> MealPlan {
		MealPlan(
			id: serverID ?? localID.uuidString,
			date: date,
			mealDescription: mealDescription
		)
	}

	/// Overwrites mutable fields from a server-fetched MealPlan and marks as synced.
	func applyServerValues(_ plan: MealPlan) {
		serverID = plan.id
		date = plan.date
		mealDescription = plan.mealDescription
		syncStatus = .synced
	}
}

// MARK: -

@Model
final class LocalReceipt {
	@Attribute(.unique) var localID: UUID
	var serverID: String?
	var syncStatus: SyncStatus

	/// Stored as "yyyy-MM-dd", matching the server wire format.
	var date: String
	var totalAmount: Double
	var purchasedBy: String
	var items: [String]
	var notes: String?

	init(
		localID: UUID = UUID(),
		serverID: String? = nil,
		syncStatus: SyncStatus = .pendingCreate,
		date: String,
		totalAmount: Double,
		purchasedBy: String,
		items: [String] = [],
		notes: String? = nil
	) {
		self.localID = localID
		self.serverID = serverID
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
			id: serverID ?? localID.uuidString,
			date: date,
			totalAmount: totalAmount,
			purchasedBy: purchasedBy,
			items: items,
			notes: notes
		)
	}

	/// Overwrites mutable fields from a server-fetched Receipt and marks as synced.
	func applyServerValues(_ receipt: Receipt) {
		serverID = receipt.id
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
	/// nil for creates until the server response is received and remapped.
	var serverID: String?
	var createdAt: Date
	var retryCount: Int
	var lastError: String?

	init(
		id: UUID = UUID(),
		entityType: SyncEntityType,
		operationType: SyncOperationType,
		payload: Data,
		localID: UUID,
		serverID: String? = nil,
		createdAt: Date = Date(),
		retryCount: Int = 0,
		lastError: String? = nil
	) {
		self.id = id
		self.entityType = entityType
		self.operationType = operationType
		self.payload = payload
		self.localID = localID
		self.serverID = serverID
		self.createdAt = createdAt
		self.retryCount = retryCount
		self.lastError = lastError
	}
}
