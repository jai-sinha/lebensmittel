//
//  GroupService.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/13/26.
//

import Foundation
import Security

// MARK: - Group Storage

actor GroupStorage {
	private let defaults = UserDefaults.standard
	private let activeGroupKey = "activeGroupId"
	private let legacyGroupMigrationCompletedKey = "legacyGroupMigrationCompleted"

	private var cachedActiveGroupId: String?
	private var cachedLegacyGroupMigrationCompleted: Bool?

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
}

// MARK: - Group Service

actor GroupService {
	static let shared = GroupService()

	struct LegacyUser: Codable, Sendable {
		let id: String
		let username: String
		let displayName: String
	}

	private let keychain = KeychainService()
	private let userKey = "user"
	private let storage = GroupStorage()
	private let session: URLSession
	private let decoder = JSONDecoder()

	init(session: URLSession = .shared) {
		self.session = session
	}

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

	func migrateLegacyGroupIfNeeded() async {
		if await storage.loadLegacyGroupMigrationCompleted() {
			return
		}

		guard let user = try? keychain.read(LegacyUser.self, forKey: userKey) else {
			await storage.saveLegacyGroupMigrationCompleted(true)
			return
		}

		do {
			let groups = try await fetchLegacyGroups(for: user.id)
			if await getActiveGroupId() == nil, let firstGroupID = groups.first {
				await storage.saveActiveGroupId(firstGroupID)
			}
			await storage.saveLegacyGroupMigrationCompleted(true)
		} catch {
			// Leave migration incomplete so it can retry on the next app launch.
		}
	}

	private func fetchLegacyGroups(for userID: String) async throws -> [String] {
		let path = "migration/users/\(userID)/groups"
		let baseURL = await AppConfig.apiBaseURL
		let url = baseURL.appendingPathComponent(path)
		let (data, response) = try await session.data(from: url)

		guard let httpResponse = response as? HTTPURLResponse else {
			throw APIError.invalidResponse
		}

		guard (200...299).contains(httpResponse.statusCode) else {
			let message = (try? decoder.decode([String: String].self, from: data))?["error"]
			throw APIError.server(statusCode: httpResponse.statusCode, message: message)
		}

		return try decoder.decode([String].self, from: data)
	}
}

// MARK: Temporary Keychain/JWT utils
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

		// Try to delete existing item first
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

		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)

		if status == errSecItemNotFound {
			return nil
		}

		guard status == errSecSuccess, let data = result as? Data else {
			throw KeychainError.osStatus(status)
		}

		return try JSONDecoder().decode(T.self, from: data)
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
