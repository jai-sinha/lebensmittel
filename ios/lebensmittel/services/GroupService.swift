//
//  GroupService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/13/26.
//

import Foundation

// MARK: - Group Storage

actor GroupStorage {
	private let defaults = UserDefaults.standard
	private let activeGroupKey = "activeGroupId"

	private var cachedActiveGroupId: String?

	func loadActiveGroupId() -> String? {
		if let cachedActiveGroupId {
			return cachedActiveGroupId
		}

		let groupId = defaults.string(forKey: activeGroupKey)
		cachedActiveGroupId = groupId
		return groupId
	}

	func saveActiveGroupId(_ id: String?) {
		cachedActiveGroupId = id

		if let id, !id.isEmpty {
			defaults.set(id, forKey: activeGroupKey)
		} else {
			defaults.removeObject(forKey: activeGroupKey)
		}
	}

	func clearActiveGroupId() {
		cachedActiveGroupId = nil
		defaults.removeObject(forKey: activeGroupKey)
	}
}

// MARK: - Group Service

actor GroupService {
	enum GroupError: Error, LocalizedError {
		case invalidResponse

		var errorDescription: String? {
			switch self {
			case .invalidResponse:
				return "Invalid server response"
			}
		}
	}

	static let shared = GroupService()

	private let storage = GroupStorage()
	private var activeGroupTask: Task<String?, Error>?

	private var apiClient: APIClient {
		APIClient(authService: AuthManager.shared)
	}

	func getUserGroups() async throws -> [AuthGroup] {
		try await apiClient.send(
			path: "/users/me/groups",
			includeGroupHeader: false
		)
	}

	func getUsersInActiveGroup() async throws -> [GroupUser] {
		guard let groupId = try await getActiveGroupId(), !groupId.isEmpty else {
			return []
		}

		return try await apiClient.send(path: "/groups/\(groupId)/users")
	}

	func getActiveGroupId() async throws -> String? {
		if let localId = await storage.loadActiveGroupId(), !localId.isEmpty {
			return localId
		}

		if let activeGroupTask {
			return try await activeGroupTask.value
		}

		let task = Task<String?, Error> {
			_ = try await AuthManager.shared.ensureAuthenticated()

			let result: [String: String] = try await apiClient.send(
				path: "/users/me/active-group",
				includeGroupHeader: false
			)

			let groupId = result["groupId"]
			await storage.saveActiveGroupId(groupId)
			return groupId
		}

		activeGroupTask = task

		do {
			let groupId = try await task.value
			activeGroupTask = nil
			return groupId
		} catch {
			activeGroupTask = nil
			throw error
		}
	}

	func setActiveGroup(_ groupId: String) async throws {
		await storage.saveActiveGroupId(groupId)

		if !groupId.isEmpty {
			let body = ["groupId": groupId]
			try? await apiClient.sendWithoutResponse(
				path: "/users/me/active-group",
				method: .PATCH,
				body: body,
				includeGroupHeader: false
			)
		}
	}

	func clearActiveGroup() async {
		await storage.clearActiveGroupId()
		clearActiveGroupTask()
	}

	func removeUserFromGroup(groupId: String, userId: String) async throws {
		try await apiClient.sendWithoutResponse(
			path: "/groups/\(groupId)/users/\(userId)",
			method: .DELETE
		)
	}

	func getGroupInviteCode(groupId: String) async throws -> String {
		let result: [String: String] = try await apiClient.send(
			path: "/groups/\(groupId)/invite",
			method: .POST
		)

		guard let inviteCode = result["code"] else {
			throw GroupError.invalidResponse
		}

		return inviteCode
	}

	func createGroup(groupName: String) async throws {
		let body = ["name": groupName]
		let group: AuthGroup = try await apiClient.send(
			path: "/groups",
			method: .POST,
			body: body
		)
		try await setActiveGroup(group.id)
	}

	func joinGroup(code: String) async throws {
		struct JoinResponse: Decodable {
			let groupId: String
		}

		let body = ["code": code]
		let result: JoinResponse = try await apiClient.send(
			path: "/groups/join",
			method: .POST,
			body: body
		)

		try await setActiveGroup(result.groupId)
	}

	func leaveGroup(groupId: String) async throws {
		try await removeUserFromGroup(groupId: groupId, userId: "me")

		if try await getActiveGroupId() == groupId {
			await storage.saveActiveGroupId(nil)
		}
	}

	func renameGroup(groupId: String, newName: String) async throws {
		let body = ["name": newName]
		try await apiClient.sendWithoutResponse(
			path: "/groups/\(groupId)",
			method: .PATCH,
			body: body
		)
	}

	private func clearActiveGroupTask() {
		activeGroupTask = nil
	}
}
