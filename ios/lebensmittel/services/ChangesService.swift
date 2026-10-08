//
//  ChangesService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 09/30/26.
//

import Foundation

/// fetches the server-originated changes for the active group
struct ChangesService {
	static let shared = ChangesService()

	private var client: APIClient { .shared }

	func fetchChanges(afterSeq: Int64?) async throws -> ChangesResponse {
		return try await client.send(
			path: "/changes",
			queryItems: afterSeq.map { [URLQueryItem(name: "afterSeq", value: String($0))] }
		)
	}
}

struct ChangesResponse: Codable {
	/// isFull means this is a full fetch of everything, vs a delta
	let isFull: Bool
	let nextSeq: Int64
	let grocery: [GroceryItem]
	let meal: [MealPlan]
	let receipt: [Receipt]
	let deletedIds: DeletedIDs
}

struct DeletedIDs: Codable {
	let grocery: [UUID]
	let meal: [UUID]
	let receipt: [UUID]
}
