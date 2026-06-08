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
	static let shared = GroupService()

	private let storage = GroupStorage()

	func getActiveGroupId() async -> String? {
		guard let groupId = await storage.loadActiveGroupId() else { return nil }
		let trimmed = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	func setActiveGroup(_ groupId: String) async {
		let trimmed = groupId.trimmingCharacters(in: .whitespacesAndNewlines)
		await storage.saveActiveGroupId(trimmed.isEmpty ? nil : trimmed)
	}

	func clearActiveGroup() async {
		await storage.clearActiveGroupId()
	}
}
