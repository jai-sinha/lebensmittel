//
//  GroupService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/13/26.
//

import Foundation

struct GroupService: GroupServicing {
	static let shared = GroupService(client: .shared)

	private struct CreateGroupRequest: Encodable {
		let name: String
	}

	private struct GroupPatchRequest: Encodable {
		let name: String?
		let categories: [String]?
		let members: [String]?
	}

	private struct GroupSeedRequest: Encodable {
		let grocery: [NewGroceryItem]
		let meal: [NewMealPlan]
		let receipt: NewReceipt?
	}

	private let client: APIClient

	nonisolated init(client: APIClient) {
		self.client = client
	}

	func fetchGroup(id: String) async throws -> AuthGroup {
		let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
		return try await client.send(
			path: "/groups/\(trimmed)",
			includeGroupHeader: false
		)
	}

	func createGroup(name: String) async throws -> AuthGroup {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		return try await client.send(
			path: "/groups",
			method: .POST,
			body: CreateGroupRequest(name: trimmed),
			includeGroupHeader: false
		)
	}

	func seedGroup(id: String) async throws {
		let today = Self.dayFormatter.string(from: Date())
		try await client.sendWithoutResponse(
			path: "/groups/seed",
			method: .POST,
			body: GroupSeedRequest(
				grocery: GroupSeed.starterGroceries.map {
					NewGroceryItem(
						id: UUID(),
						name: $0.name,
						category: $0.category,
						isNeeded: false
					)
				},
				meal: [
					NewMealPlan(
						id: UUID(),
						date: today,
						mealDescription: "Example Meal"
					)
				],
				receipt: NewReceipt(
					id: UUID(),
					date: today,
					totalAmount: 42.67,
					purchasedBy: "Default",
					items: GroupSeed.exampleReceiptItems,
					notes: "Example receipt, feel free to delete me!"
				)
			)
		)
	}

	private static let dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	func renameGroup(id: String, name: String) async throws -> AuthGroup {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		return try await patchGroup(
			id: id,
			request: GroupPatchRequest(name: trimmed, categories: nil, members: nil)
		)
	}

	func updateGroupCategories(id: String, categories: [String]) async throws -> AuthGroup {
		return try await patchGroup(
			id: id,
			request: GroupPatchRequest(
				name: nil,
				categories: normalizeGroupValues(categories),
				members: nil
			)
		)
	}

	func updateGroupMembers(id: String, members: [String]) async throws -> AuthGroup {
		return try await patchGroup(
			id: id,
			request: GroupPatchRequest(
				name: nil,
				categories: nil,
				members: normalizeGroupValues(members)
			)
		)
	}

	func fetchLegacyGroups(for userID: String) async throws -> [String] {
		try await client.send(
			path: "/migration/users/\(userID)/groups",
			includeGroupHeader: false
		)
	}

	private func patchGroup(id: String, request: GroupPatchRequest) async throws -> AuthGroup {
		try await client.send(
			path: "/groups/\(id)",
			method: .PATCH,
			body: request,
			includeGroupHeader: false
		)
	}

	private func normalizeGroupValues(_ values: [String]) -> [String] {
		values
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
	}
}
