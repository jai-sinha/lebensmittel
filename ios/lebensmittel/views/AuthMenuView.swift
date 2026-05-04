//
//  AuthMenuView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/08/26.
//

import SwiftUI

struct AuthMenuView: View {
	@Environment(SessionManager.self) var sessionManager
	@State private var model = AuthMenuModel()
	@State private var showLoginSheet = false

	private var isOffline: Bool {
		!ConnectivityMonitor.shared.isOnline
	}

	var body: some View {
		if !sessionManager.isAuthenticated {
			Button {
				showLoginSheet = true
			} label: {
				Image(systemName: "person.circle")
					.imageScale(.large)
			}
			.sheet(isPresented: $showLoginSheet) {
				LoginView(sessionManager: sessionManager)
			}
		} else {
			let isOffline = !ConnectivityMonitor.shared.isOnline
			Menu {
				// MARK: - User Info
				if let user = sessionManager.currentUser {
					Section(user.displayName) {
						Button(role: .destructive) {
							sessionManager.logout()
						} label: {
							Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
						}
						Button(role: .destructive) {
							model.activeAlert = .deleteUser
						} label: {
							Label("Delete Account", systemImage: "trash")
						}
					}
				}

				// MARK: - Group Selection
				let groups = sessionManager.currentUserGroups
				let activeGroupId = sessionManager.currentUserActiveGroupId

				Section("Groups") {
					if !groups.isEmpty {
						if isOffline {
							Text("Group actions are unavailable while offline.")
								.foregroundStyle(.secondary)
						}

						ForEach(groups) { group in
							GroupRow(
								group: group,
								isActive: group.id == activeGroupId,
								isDisabled: isOffline,
								onSwitch: {
									model.switchGroup(
										to: group.id, sessionManager: sessionManager)
								},
								onRename: {
									model.groupToRename = group
									model.renamedGroupName = group.name
									model.activeAlert = .rename
								},
								onLeave: {
									model.leaveGroup(group, sessionManager: sessionManager)
								},
								onInvite: {
									model.getGroupInviteCode(group)
								}
							)
						}
					} else {
						Text("No Groups Available")
					}
				}

				// MARK: - Group Actions
				Section {
					Button {
						model.activeAlert = .join
					} label: {
						Label("Join Group", systemImage: "person.badge.plus")
					}
					.disabled(isOffline)
				}
				Section {
					Button {
						model.activeAlert = .create
					} label: {
						Label("Create Group", systemImage: "plus.circle")
					}
					.disabled(isOffline)
				}
			} label: {
				Image(systemName: "person.circle")
					.imageScale(.large)
			}
			.alert(
				model.activeAlert?.title ?? "",
				isPresented: Binding(
					get: { model.activeAlert != nil },
					set: { if !$0 { model.activeAlert = nil } }
				)
			) {
				alertContent()
			} message: {
				alertMessage()
			}
		}
	}

	// MARK: - Alert Content

	@ViewBuilder
	private func alertContent() -> some View {
		switch model.activeAlert {
		case .join:
			TextField("Invite Code", text: $model.joinCode)
			Button("Cancel", role: .cancel) {
				model.joinCode = ""
			}
			Button("Join") {
				model.joinGroup(sessionManager: sessionManager)
			}
		case .rename:
			TextField("Group Name", text: $model.renamedGroupName)
			Button("Cancel", role: .cancel) {
				model.groupToRename = nil
				model.renamedGroupName = ""
			}
			Button("Rename") {
				if let group = model.groupToRename {
					model.renameGroup(
						group: group, newName: model.renamedGroupName,
						sessionManager: sessionManager)
				}
			}
		case .create:
			TextField("Group Name", text: $model.createdGroupName)
			Button("Cancel", role: .cancel) {
				model.createdGroupName = ""
			}
			Button("Create") {
				if !model.createdGroupName.isEmpty {
					model.createGroup(sessionManager: sessionManager)
				}
			}
		case .inviteCode:
			Button("Copy Code") {
				model.copyInviteCode()
			}
		case .deleteUser:
			Button("Cancel", role: .cancel) {
				model.activeAlert = nil
			}
			Button("Delete", role: .destructive) {
				model.deleteUser(sessionManager: sessionManager)
			}
		case .error:
			Button("OK", role: .cancel) {
				model.errorMessage = nil
			}
		case .none:
			EmptyView()
		}
	}

	@ViewBuilder
	private func alertMessage() -> some View {
		switch model.activeAlert {
		case .join:
			Text("Enter the code for the group you want to join.")
		case .deleteUser:
			Text(
				"This will permanently delete your account and sign you out. This action cannot be undone."
			)
		case .error(let message):
			Text(message)
		case .inviteCode:
			Text("Your invite code is: \(model.inviteCode)")
		default:
			EmptyView()
		}
	}
}

struct GroupRow: View {
	let group: AuthGroup
	let isActive: Bool
	let isDisabled: Bool
	let onSwitch: () -> Void
	let onRename: () -> Void
	let onLeave: () -> Void
	let onInvite: () -> Void

	var body: some View {
		Menu {
			if !isActive {
				Button("Switch to this group") {
					onSwitch()
				}
				.disabled(isDisabled)
			}

			Button("Get group invite code") {
				onInvite()
			}

			Button("Rename group") {
				onRename()
			}

			Button(role: .destructive) {
				onLeave()
			} label: {
				Text("Leave group")
			}
		} label: {
			if isActive {
				Label(group.name, systemImage: "checkmark.circle.fill")
			} else {
				Label(group.name, systemImage: "circle")
			}
		}
		.disabled(isDisabled)
	}
}
