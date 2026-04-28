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
	var isAuthenticated = false
	var isGuest = false
	var currentUser: User?
	var currentUserGroups: [AuthGroup] = []
	var currentUserActiveGroupId: String?
	var currentGroupUsers: [GroupUser] = []
	var isCheckingAuth = true
	var errorMessage: String?

	func checkAuthentication() {
		Task {
			await bootstrap()
		}
	}

	func bootstrap() async {
		isCheckingAuth = true

		do {
			try await hydrateSession()
		} catch {
			clearLocalState()
		}

		isCheckingAuth = false
	}

	func hydrateSession() async throws {
		let user = try await AuthManager.shared.ensureAuthenticated()
		async let groupsTask = GroupService.shared.getUserGroups()
		async let activeGroupIdTask = GroupService.shared.getActiveGroupId()

		let groups = try await groupsTask
		let activeGroupId = try await activeGroupIdTask
		let groupUsers: [GroupUser]

		if let activeGroupId, !activeGroupId.isEmpty {
			groupUsers = try await GroupService.shared.getUsersInActiveGroup()
		} else {
			groupUsers = []
		}

		isAuthenticated = true
		isGuest = false
		currentUser = user
		currentUserGroups = groups
		currentUserActiveGroupId = activeGroupId
		currentGroupUsers = groupUsers
		errorMessage = nil
	}

	func refreshState() async {
		do {
			try await hydrateSession()
		} catch {
			errorMessage = UserFacingError.message(for: error)
			clearLocalState()
		}
	}

	func refreshGroupContext() async {
		do {
			let activeGroupId = try await GroupService.shared.getActiveGroupId()
			let groupUsers = try await GroupService.shared.getUsersInActiveGroup()

			currentUserActiveGroupId = activeGroupId
			currentGroupUsers = groupUsers
			errorMessage = nil
		} catch {
			errorMessage = UserFacingError.message(for: error)
		}
	}

	func logout() {
		Task {
			do {
				try await AuthManager.shared.logout()
				clearLocalState()
			} catch {
				errorMessage = UserFacingError.message(for: error)
			}
		}
	}

	func clearLocalState() {
		SyncEngine.shared.clearLocalData()
		isAuthenticated = false
		isGuest = false
		currentUser = nil
		currentUserGroups = []
		currentUserActiveGroupId = nil
		currentGroupUsers = []
		errorMessage = nil
	}

	func continueAsGuest() {
		isGuest = true
	}

	func exitGuestMode() {
		isGuest = false
	}
}
