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
	var isReady = false
	var errorMessage: String?

	var hasActiveGroup: Bool {
		guard let activeGroupId else { return false }
		return !activeGroupId.isEmpty
	}

	func bootstrap() {
		Task {
			activeGroupId = await GroupService.shared.getActiveGroupId()
			isReady = true
			errorMessage = nil
		}
	}

	func refreshGroupContext() async {
		activeGroupId = await GroupService.shared.getActiveGroupId()
		errorMessage = nil
	}

	func setActiveGroup(_ groupId: String) {
		Task {
			await GroupService.shared.setActiveGroup(groupId)
			await refreshGroupContext()
			NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
		}
	}

	func clearActiveGroup() {
		Task {
			await GroupService.shared.clearActiveGroup()
			SyncEngine.shared.clearLocalData()
			activeGroupId = nil
			errorMessage = nil
			NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
		}
	}
}
