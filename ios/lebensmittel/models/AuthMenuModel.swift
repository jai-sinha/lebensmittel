//
//  AuthMenuModel.swift
//  lebensmittel
//
//  Created by Jai Sinha on 02/04/26.
//

import Foundation
import SwiftUI

enum ActiveAlert: Equatable {
	case join
	case rename
	case create
	case inviteCode
	case deleteUser
	case error(String)

	var title: String {
		switch self {
		case .join: "Join Group"
		case .rename: "Rename Group"
		case .create: "Create Group"
		case .inviteCode: "Invite Code"
		case .error: "Error"
		case .deleteUser: "Delete Account"
		}
	}
}

@MainActor
@Observable
class AuthMenuModel {
	var joinCode: String = ""
	var errorMessage: String?
	var createdGroupName: String = ""
	var inviteCode: String = ""
	var groupToRename: AuthGroup?
	var renamedGroupName: String = ""
	var activeAlert: ActiveAlert?

	// MARK: - Actions

	func switchGroup(to groupId: String, sessionManager: SessionManager) {
		Task {
			do {
				try await GroupService.shared.setActiveGroup(groupId)
				await sessionManager.refreshGroupContext()
				NotificationCenter.default.post(
					name: Notification.Name("GroupChanged"), object: nil)
			} catch {
				await MainActor.run {
					errorMessage = UserFacingError.message(for: error)
					activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
				}
			}
		}
	}

	func renameGroup(group: AuthGroup, newName: String, sessionManager: SessionManager) {
		Task {
			do {
				try await GroupService.shared.renameGroup(groupId: group.id, newName: newName)
				try await sessionManager.hydrateSession()
				await MainActor.run {
					groupToRename = nil
					renamedGroupName = ""
				}
			} catch {
				await MainActor.run {
					errorMessage = UserFacingError.message(for: error)
					activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
				}
			}
		}
	}

	func joinGroup(sessionManager: SessionManager) {
		guard !joinCode.isEmpty else { return }

		Task {
			do {
				try await GroupService.shared.joinGroup(code: joinCode)
				await MainActor.run {
					joinCode = ""
				}
				try await sessionManager.hydrateSession()
				NotificationCenter.default.post(
					name: Notification.Name("GroupChanged"), object: nil)
			} catch {
				await MainActor.run {
					errorMessage = UserFacingError.message(for: error)
					activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
				}
			}
		}
	}

	func getGroupInviteCode(_ group: AuthGroup) {
		Task {
			do {
				let code = try await GroupService.shared.getGroupInviteCode(groupId: group.id)
				await MainActor.run {
					inviteCode = code
					activeAlert = .inviteCode
				}
			} catch {
				await MainActor.run {
					errorMessage = UserFacingError.message(for: error)
					activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
				}
			}
		}
	}

	func copyInviteCode() {
		UIPasteboard.general.string = inviteCode
		inviteCode = ""
	}

	func createGroup(sessionManager: SessionManager) {
		guard !createdGroupName.isEmpty else { return }

		Task {
			do {
				try await GroupService.shared.createGroup(groupName: createdGroupName)
				await MainActor.run {
					createdGroupName = ""
				}
				try await sessionManager.hydrateSession()
				NotificationCenter.default.post(
					name: Notification.Name("GroupChanged"), object: nil)
			} catch {
				await MainActor.run {
					errorMessage = UserFacingError.message(for: error)
					activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
				}
			}
		}
	}

	func leaveGroup(_ group: AuthGroup, sessionManager: SessionManager) {
		Task {
			do {
				let didLeaveActive = sessionManager.currentUserActiveGroupId == group.id

				try await GroupService.shared.leaveGroup(groupId: group.id)

				if didLeaveActive {
					try await sessionManager.hydrateSession()
					NotificationCenter.default.post(
						name: Notification.Name("GroupChanged"), object: nil)
				} else {
					try await sessionManager.hydrateSession()
				}
			} catch {
				await MainActor.run {
					errorMessage = UserFacingError.message(for: error)
					activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
				}
			}
		}
	}

	func deleteUser(sessionManager: SessionManager) {
		Task {
			do {
				try await AuthManager.shared.deleteAccount()
				await MainActor.run {
					activeAlert = nil
					sessionManager.clearLocalState()
				}
			} catch {
				await MainActor.run {
					errorMessage = UserFacingError.message(for: error)
					activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
				}
			}
		}
	}
}
