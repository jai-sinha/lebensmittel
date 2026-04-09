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

    func switchGroup(to groupId: String, authStateManager: AuthStateManager) {
        Task {
            do {
                try await AuthManager.shared.setActiveGroup(groupId)
                await authStateManager.refreshState()
                // Post notification to let other views know they should refresh data
                NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
            } catch {
                await MainActor.run {
                    errorMessage = UserFacingError.message(for: error)
                    activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
                }
            }
        }
    }

    func renameGroup(group: AuthGroup, newName: String, authStateManager: AuthStateManager) {
        Task {
            do {
                try await AuthManager.shared.renameGroup(groupId: group.id, newName: newName)
                await MainActor.run {
                    authStateManager.checkAuthentication()
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

    func joinGroup(authStateManager: AuthStateManager) {
        guard !joinCode.isEmpty else { return }

        Task {
            do {
                try await AuthManager.shared.joinGroup(code: joinCode)
                await MainActor.run {
                    joinCode = ""
                }
                await authStateManager.refreshState()
                NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
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
                let code = try await AuthManager.shared.getGroupInviteCode(groupId: group.id)
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

    func createGroup(authStateManager: AuthStateManager) {
        guard !createdGroupName.isEmpty else { return }
        Task {
            do {
                try await AuthManager.shared.createGroup(groupName: createdGroupName)
                await MainActor.run {
                    createdGroupName = ""
                }
                await authStateManager.refreshState()
                NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
            } catch {
                await MainActor.run {
                    errorMessage = UserFacingError.message(for: error)
                    activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
                }
            }
        }
    }

    func leaveGroup(_ group: AuthGroup, authStateManager: AuthStateManager) {
        Task {
            do {
                try await AuthManager.shared.leaveGroup(groupId: group.id)

                var didLeaveActive = false
                if authStateManager.currentUserActiveGroupId == group.id {
                     try await AuthManager.shared.setActiveGroup("")
                     didLeaveActive = true
                }

                await authStateManager.refreshState()

                if didLeaveActive {
                     NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
                }
            } catch {
                await MainActor.run {
                    errorMessage = UserFacingError.message(for: error)
                    activeAlert = .error(errorMessage ?? "Something went wrong. Please try again.")
                }
            }
        }
    }

    func deleteUser(authStateManager: AuthStateManager) {
		Task {
			do {
				// deleteAccount() calls logout() internally, which clears all
				// keychain storage and in-memory caches before returning.
				try await AuthManager.shared.deleteAccount()
				await MainActor.run {
					activeAlert = nil
					// Use clearLocalState() rather than logout() to avoid
					// redundantly hitting the keychain a second time.
					authStateManager.clearLocalState()
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
