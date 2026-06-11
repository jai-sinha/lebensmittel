//
//  SessionManager.swift
//  lebensmittel
//
//  Created by Jai Sinha on 04/13/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
	var activeGroupId: String?
	var knownGroups: [AuthGroup] = []
	var isReady = false
	var errorMessage: String?

	var hasActiveGroup: Bool {
		guard let activeGroupId else { return false }
		return !activeGroupId.isEmpty
	}

	func bootstrap() {
		Task {
			await reloadFromGroupModel()
			isReady = true
		}
	}

	func refreshGroupContext() async {
		await reloadFromGroupModel()
	}

	func setActiveGroup(_ groupId: String) {
		Task {
			await GroupModel.shared.setActiveGroup(groupId)
			await finalizeGroupChange()
		}
	}

	func setActiveGroup(_ group: AuthGroup) {
		Task {
			await GroupModel.shared.setActiveGroup(group)
			await finalizeGroupChange()
		}
	}

	func createGroup(name: String) async throws {
		_ = try await GroupModel.shared.createGroup(name: name)
		await finalizeGroupChange()
	}

	func renameGroup(id: String, name: String) async throws {
		_ = try await GroupModel.shared.renameGroup(id: id, name: name)
		await reloadFromGroupModel()
	}

	func updateGroupCategories(id: String, categories: [String]) async throws {
		_ = try await GroupModel.shared.updateGroupCategories(id: id, categories: categories)
		await reloadFromGroupModel()
		NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
	}

	func updateGroupMembers(id: String, members: [String]) async throws {
		_ = try await GroupModel.shared.updateGroupMembers(id: id, members: members)
		await reloadFromGroupModel()
		NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
	}

	func clearActiveGroup() {
		Task {
			await GroupModel.shared.clearActiveGroup()
			await finalizeGroupChange()
		}
	}

	private func finalizeGroupChange() async {
		await reloadFromGroupModel()
		NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
	}

	private func reloadFromGroupModel() async {
		let snapshot = await GroupModel.shared.activeGroupSnapshot()
		activeGroupId = snapshot.activeGroupId
		knownGroups = snapshot.knownGroups
		errorMessage = nil
	}
}
