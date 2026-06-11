//
//  GroupModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 06/11/26.
//

import Foundation
import Security

actor GroupStore {
	nonisolated(unsafe) static let shared = GroupStore()

	private let defaults = UserDefaults.standard
	private let activeGroupKey = "activeGroupId"
	private let knownGroupsKey = "knownGroups"
	private let legacyGroupMigrationCompletedKey = "legacyGroupMigrationCompleted"

	private var cachedActiveGroupId: String?
	private var cachedKnownGroups: [AuthGroup]?
	private var cachedLegacyGroupMigrationCompleted: Bool?

	func loadActiveGroupId() -> String? {
		if let cachedActiveGroupId {
			return cachedActiveGroupId
		}

		let groupId = defaults.string(forKey: activeGroupKey)
		cachedActiveGroupId = groupId?.trimmedNilIfEmpty
		return cachedActiveGroupId
	}

	func saveActiveGroupId(_ id: String?) {
		let trimmed = id?.trimmedNilIfEmpty
		cachedActiveGroupId = trimmed

		if let trimmed {
			defaults.set(trimmed, forKey: activeGroupKey)
		} else {
			defaults.removeObject(forKey: activeGroupKey)
		}
	}

	func clearActiveGroupId() {
		cachedActiveGroupId = nil
		defaults.removeObject(forKey: activeGroupKey)
	}

	func loadKnownGroups() -> [AuthGroup] {
		if let cachedKnownGroups {
			return cachedKnownGroups
		}

		let groups = loadKnownGroupsFromDefaults()
		cachedKnownGroups = groups
		return groups
	}

	func saveKnownGroups(_ groups: [AuthGroup]) {
		cachedKnownGroups = groups
		if let data = try? JSONEncoder().encode(groups) {
			defaults.set(data, forKey: knownGroupsKey)
		} else {
			defaults.removeObject(forKey: knownGroupsKey)
		}
	}

	func loadLegacyGroupMigrationCompleted() -> Bool {
		if let cachedLegacyGroupMigrationCompleted {
			return cachedLegacyGroupMigrationCompleted
		}

		let completed = defaults.bool(forKey: legacyGroupMigrationCompletedKey)
		cachedLegacyGroupMigrationCompleted = completed
		return completed
	}

	func saveLegacyGroupMigrationCompleted(_ completed: Bool) {
		cachedLegacyGroupMigrationCompleted = completed
		defaults.set(completed, forKey: legacyGroupMigrationCompletedKey)
	}

	private func loadKnownGroupsFromDefaults() -> [AuthGroup] {
		guard let data = defaults.data(forKey: knownGroupsKey),
			let groups = try? JSONDecoder().decode([AuthGroup].self, from: data)
		else {
			return []
		}
		return groups
	}
}

actor GroupModel {
	nonisolated(unsafe) static let shared = GroupModel(
		service: GroupService(client: .shared),
		store: .shared,
		keychain: KeychainService()
	)

	private struct LegacyUser: Codable, Sendable {
		let id: String
		let username: String
		let displayName: String
	}

	private let service: any GroupServicing
	private let store: GroupStore
	private let keychain: KeychainService
	private let userKey = "user"

	init(
		service: any GroupServicing,
		store: GroupStore,
		keychain: KeychainService
	) {
		self.service = service
		self.store = store
		self.keychain = keychain
	}

	func getActiveGroupId() async -> String? {
		await store.loadActiveGroupId()
	}

	func getKnownGroups() async -> [AuthGroup] {
		await store.loadKnownGroups()
	}

	func activeGroupSnapshot() async -> GroupSnapshot {
		async let activeGroupId = store.loadActiveGroupId()
		async let knownGroups = store.loadKnownGroups()
		return await GroupSnapshot(
			activeGroupId: activeGroupId,
			knownGroups: knownGroups
		)
	}

	/// Persists the active group selection and keeps the known-groups cache in sync.
	/// UI refresh, notifications, and local data resets belong to higher layers.
	func setActiveGroup(_ groupId: String) async {
		let trimmed = groupId.trimmedNilIfEmpty
		guard let trimmed else {
			await store.saveActiveGroupId(nil)
			return
		}

		await store.saveActiveGroupId(trimmed)
		await ensureKnownGroup(AuthGroup(id: trimmed, name: trimmed))
	}

	func setActiveGroup(_ group: AuthGroup) async {
		await upsertKnownGroup(group)
		await store.saveActiveGroupId(group.id)
	}

	func clearActiveGroup() async {
		await store.clearActiveGroupId()
	}

	/// Fetches a group from the backend and persists it as the active selection.
	/// Callers are responsible for reacting to the changed group context.
	func fetchGroup(id: String) async throws {
		let group = try await service.fetchGroup(id: id)
		await setActiveGroup(group)
	}

	func createGroup(name: String) async throws -> AuthGroup {
		let group = try await service.createGroup(name: name)
		await setActiveGroup(group)
		return group
	}

	func renameGroup(id: String, name: String) async throws -> AuthGroup {
		let group = try await service.renameGroup(id: id, name: name)
		await upsertKnownGroup(group)
		return group
	}

	func updateGroupCategories(id: String, categories: [String]) async throws -> AuthGroup {
		let group = try await service.updateGroupCategories(id: id, categories: categories)
		await upsertKnownGroup(group)
		return group
	}

	func updateGroupMembers(id: String, members: [String]) async throws -> AuthGroup {
		let group = try await service.updateGroupMembers(id: id, members: members)
		await upsertKnownGroup(group)
		return group
	}

	/// One-time migration from legacy keychain-backed user membership to the
	/// current persisted group cache.
	func migrateLegacyGroupIfNeeded() async {
		if await store.loadLegacyGroupMigrationCompleted() {
			return
		}

		guard let user = try? keychain.read(LegacyUser.self, forKey: userKey) else {
			await store.saveLegacyGroupMigrationCompleted(true)
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

			if !recoveredGroups.isEmpty {
				await mergeKnownGroups(recoveredGroups)
			}
			if await getActiveGroupId() == nil, let firstGroup = recoveredGroups.first {
				await setActiveGroup(firstGroup)
			}
			await store.saveLegacyGroupMigrationCompleted(true)
		} catch {
			// Leave migration incomplete so it can retry on the next app launch.
		}
	}

	private func mergeKnownGroups(_ groups: [AuthGroup]) async {
		let existing = await store.loadKnownGroups()
		var mergedByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
		for group in groups {
			mergedByID[group.id] = group
		}
		let merged = mergedByID.values.sorted { lhs, rhs in
			lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
		}
		await store.saveKnownGroups(merged)
	}

	private func ensureKnownGroup(_ group: AuthGroup) async {
		let groups = await store.loadKnownGroups()
		guard !groups.contains(where: { $0.id == group.id }) else { return }
		await store.saveKnownGroups(groups + [group])
	}

	private func upsertKnownGroup(_ group: AuthGroup) async {
		await mergeKnownGroups([group])
	}
}

struct GroupSnapshot: Sendable {
	let activeGroupId: String?
	let knownGroups: [AuthGroup]
}

private extension String {
	nonisolated var trimmedNilIfEmpty: String? {
		let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
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
