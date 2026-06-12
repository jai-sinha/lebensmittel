//
//  GroupModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 06/11/26.
//

import Foundation
import Observation
import Security
import SwiftData


@MainActor
@Observable
final class GroupModel {
	static let shared = GroupModel(
		service: GroupService(client: .shared),
		keychain: KeychainService()
	)

	private struct LegacyUser: Codable, Sendable {
		let id: String
		let username: String
		let displayName: String
	}

	private let service: any GroupServicing
	private let keychain: KeychainService
	private let store: GroupStore
	private let userKey = "user"

	var activeGroupId: String?
	var knownGroups: [AuthGroup] = []
	var errorMessage: String?
	var isLoading = false

	var hasActiveGroup: Bool {
		guard let activeGroupId else { return false }
		return !activeGroupId.isEmpty
	}

	var activeGroup: AuthGroup? {
		guard let activeGroupId else { return nil }
		return knownGroups.first(where: { $0.id == activeGroupId })
			?? AuthGroup(id: activeGroupId, name: activeGroupId)
	}

	init(
		service: any GroupServicing,
		keychain: KeychainService,
		store: GroupStore = .shared
	) {
		self.service = service
		self.keychain = keychain
		self.store = store
	}

	func configure(modelContext: ModelContext) {
		store.configure(modelContext: modelContext)
		loadPersistedStateIfNeeded()
	}

	func bootstrap() async {
		loadPersistedStateIfNeeded()
		await migrateLegacyGroupIfNeeded()
	}

	func getActiveGroupId() -> String? {
		loadPersistedStateIfNeeded()
		return activeGroupId
	}

	func activeGroupSnapshot() -> GroupSnapshot {
		loadPersistedStateIfNeeded()
		return GroupSnapshot(activeGroupId: activeGroupId, knownGroups: knownGroups)
	}

	func setActiveGroup(_ groupId: String) {
		loadPersistedStateIfNeeded()
		let trimmed = groupId.trimmedNilIfEmpty
		let previousGroupID = activeGroupId

		activeGroupId = trimmed
		if let trimmed, !knownGroups.contains(where: { $0.id == trimmed }) {
			knownGroups = sortGroups(knownGroups + [AuthGroup(id: trimmed, name: trimmed)])
		}

		persistState()
		if previousGroupID != activeGroupId {
			notifyGroupChanged()
		}
	}

	func clearActiveGroup() {
		loadPersistedStateIfNeeded()
		let hadActiveGroup = activeGroupId != nil
		activeGroupId = nil
		persistState()

		if hadActiveGroup {
			notifyGroupChanged()
		}
	}

	func fetchGroup(id: String) async throws {
		let group = try await service.fetchGroup(id: id)
		setActiveGroup(group.id)
		upsertKnownGroup(group)
		persistState()
	}

	func refreshActiveGroup() async throws -> AuthGroup? {
		loadPersistedStateIfNeeded()
		guard let activeGroupId else { return nil }

		let group = try await service.fetchGroup(id: activeGroupId)
		upsertKnownGroup(group)
		persistState()
		return group
	}

	func createGroup(name: String) async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }

		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }

		do {
			let group = try await service.createGroup(name: trimmed)
			setActiveGroup(group.id)
			upsertKnownGroup(group)
			persistState()
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func renameGroup(id: String, name: String) async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }

		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }

		do {
			try await applyGroupUpdate {
				try await service.renameGroup(id: id, name: trimmed)
			}
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func updateGroupCategories(id: String, categories: [String]) async throws -> AuthGroup {
		try await applyGroupUpdate {
			try await service.updateGroupCategories(id: id, categories: categories)
		}
	}

	func updateGroupMembers(id: String, members: [String]) async throws -> AuthGroup {
		try await applyGroupUpdate {
			try await service.updateGroupMembers(id: id, members: members)
		}
	}

	// MARK: - Group item management

	func normalizedGroupValues(_ values: [String]) -> [String] {
		values
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
	}

	func containsDuplicate(
		_ candidate: String,
		in values: [String],
		excluding excludedIndex: Int? = nil
	) -> Bool {
		values.enumerated().contains { index, value in
			index != excludedIndex && value.localizedCaseInsensitiveCompare(candidate) == .orderedSame
		}
	}

	func saveGroupItem(value: String, kind: GroupItemKind, index: Int?) async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }

		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, let activeGroup else { return }

		let rawValues = kind == .category ? activeGroup.categories : activeGroup.members
		let normalized = normalizedGroupValues(rawValues)

		if let index {
			guard normalized.indices.contains(index) else { return }
			if normalized[index].localizedCaseInsensitiveCompare(trimmed) == .orderedSame { return }
			if containsDuplicate(trimmed, in: normalized, excluding: index) {
				errorMessage = "\(kind.title) \"\(trimmed)\" already exists."
				return
			}
		} else {
			if containsDuplicate(trimmed, in: normalized) {
				errorMessage = "\(kind.title) \"\(trimmed)\" already exists."
				return
			}
		}

		var updatedValues = kind == .category ? activeGroup.categories : activeGroup.members
		if let index {
			updatedValues[index] = trimmed
		} else {
			updatedValues.append(trimmed)
		}

		do {
			try await applyGroupUpdate {
				switch kind {
				case .category:
					try await service.updateGroupCategories(id: activeGroup.id, categories: updatedValues)
				case .member:
					try await service.updateGroupMembers(id: activeGroup.id, members: updatedValues)
				}
			}
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func deleteGroupItem(at index: Int, kind: GroupItemKind) async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }

		guard let activeGroup else { return }
		var updatedValues = kind == .category ? activeGroup.categories : activeGroup.members
		guard updatedValues.indices.contains(index) else { return }
		updatedValues.remove(at: index)

		do {
			try await applyGroupUpdate {
				switch kind {
				case .category:
					try await service.updateGroupCategories(id: activeGroup.id, categories: updatedValues)
				case .member:
					try await service.updateGroupMembers(id: activeGroup.id, members: updatedValues)
				}
			}
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func setCategories(_ categories: [String]) async {
		guard let activeGroup else { return }
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }

		do {
			try await applyGroupUpdate {
				try await service.updateGroupCategories(id: activeGroup.id, categories: categories)
			}
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func joinGroup(id: String) async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }

		let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }

		// Persist locally and set active immediately (offline-first)
		setActiveGroup(trimmed)

		// Try to fetch full group details from server
		do {
			let group = try await service.fetchGroup(id: trimmed)
			upsertKnownGroup(group)
			activeGroupId = group.id
			persistState()
			notifyGroupChanged()
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func switchToGroup(_ group: AuthGroup) async {
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }
		setActiveGroup(group.id)
		upsertKnownGroup(group)
		persistState()
	}

	func leaveGroup(id: String) {
		knownGroups.removeAll { $0.id == id }
		if activeGroupId == id {
			activeGroupId = nil
		}
		persistState()
		notifyGroupChanged()
	}

	func migrateLegacyGroupIfNeeded() async {
		loadPersistedStateIfNeeded()
		guard !store.legacyGroupMigrationCompleted else { return }

		guard let user = try? keychain.read(LegacyUser.self, forKey: userKey) else {
			persistState(legacyGroupMigrationCompleted: true)
			return
		}

		do {
			let groupIDs = try await service.fetchLegacyGroups(for: user.id)
			var recoveredGroups: [AuthGroup] = []

			for groupID in groupIDs {
				if let group = try? await service.fetchGroup(id: groupID) {
					recoveredGroups.append(group)
				} else {
					recoveredGroups.append(AuthGroup(id: groupID, name: groupID))
				}
			}

			for group in recoveredGroups {
				upsertKnownGroup(group)
			}
			if activeGroupId == nil, let firstGroup = recoveredGroups.first {
				activeGroupId = firstGroup.id
			}

			persistState(legacyGroupMigrationCompleted: true)
		} catch {
			// Leave migration incomplete so it can retry on the next app launch.
		}
	}

	// MARK: - Private

	private var didLoadPersistedState = false

	private func loadPersistedStateIfNeeded() {
		guard !didLoadPersistedState else { return }
		let snapshot = store.loadSnapshot()
		activeGroupId = snapshot.activeGroupId
		knownGroups = snapshot.knownGroups
		didLoadPersistedState = true
	}

	private func persistState(legacyGroupMigrationCompleted: Bool? = nil) {
		let completed = legacyGroupMigrationCompleted ?? store.legacyGroupMigrationCompleted
		store.save(
			activeGroupId: activeGroupId,
			knownGroups: knownGroups,
			legacyGroupMigrationCompleted: completed
		)
	}

	@discardableResult
	private func applyGroupUpdate(_ update: () async throws -> AuthGroup) async rethrows -> AuthGroup {
		let group = try await update()
		upsertKnownGroup(group)
		persistState()
		return group
	}

	private func upsertKnownGroup(_ group: AuthGroup) {
		if let index = knownGroups.firstIndex(where: { $0.id == group.id }) {
			knownGroups[index] = group
		} else {
			knownGroups.append(group)
		}
		knownGroups = sortGroups(knownGroups)
	}

	private func sortGroups(_ groups: [AuthGroup]) -> [AuthGroup] {
		groups.sorted { lhs, rhs in
			lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
		}
	}

	private func notifyGroupChanged() {
		NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
	}
}

struct GroupSnapshot: Sendable {
	let activeGroupId: String?
	let knownGroups: [AuthGroup]
}

enum GroupItemKind: String, Sendable {
	case category
	case member

	var title: String {
		switch self {
		case .category: "Category"
		case .member: "Member"
		}
	}

	var placeholder: String {
		switch self {
		case .category: "Category name"
		case .member: "Member name"
		}
	}
}

struct KeychainService: Sendable {
	enum KeychainError: Error {
		case osStatus(OSStatus)
		case encodingFailed
		case decodingFailed
		case itemNotFound
	}

	private let serviceName = "com.lebensmittel.auth"

	nonisolated init() {}

	nonisolated func save<T: Codable>(_ value: T, forKey key: String) throws {
		let data = try JSONEncoder().encode(value)
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: serviceName,
			kSecAttrAccount: key,
			kSecValueData: data,
			kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
		]

		SecItemDelete(query as CFDictionary)

		let status = SecItemAdd(query as CFDictionary, nil)
		guard status == errSecSuccess else {
			throw KeychainError.osStatus(status)
		}
	}

	nonisolated func read<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: serviceName,
			kSecAttrAccount: key,
			kSecReturnData: kCFBooleanTrue!,
			kSecMatchLimit: kSecMatchLimitOne,
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		guard status != errSecItemNotFound else {
			return nil
		}

		guard status == errSecSuccess else {
			throw KeychainError.osStatus(status)
		}

		guard let data = item as? Data else {
			throw KeychainError.decodingFailed
		}

		do {
			return try JSONDecoder().decode(type, from: data)
		} catch {
			throw KeychainError.decodingFailed
		}
	}

	nonisolated func delete(forKey key: String) throws {
		let query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: serviceName,
			kSecAttrAccount: key,
		]

		let status = SecItemDelete(query as CFDictionary)
		guard status == errSecSuccess || status == errSecItemNotFound else {
			throw KeychainError.osStatus(status)
		}
	}
}
