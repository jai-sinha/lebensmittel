//
//  AuthMenuView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/08/26.
//

import SwiftUI

struct AuthMenuView: View {
    @Environment(AuthStateManager.self) var authStateManager
    @State private var model = AuthMenuModel()

    var body: some View {
        Menu {
            // MARK: - User Info
            if let user = authStateManager.currentUser {
                Section(user.displayName) {
                    Button(role: .destructive) {
                        authStateManager.logout()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }

            // MARK: - Group Selection
            let groups = authStateManager.currentUserGroups
            let activeGroupId =  authStateManager.currentUserActiveGroupId

            Section("Groups") {
                if !groups.isEmpty {
                    ForEach(groups) { group in
                        GroupRow(
                            group: group,
                            isActive: group.id == activeGroupId,
                            onSwitch: {
                                model.switchGroup(to: group.id, authStateManager: authStateManager)
                            },
                            onRename: {
                                model.groupToRename = group
                                model.renamedGroupName = group.name
                                model.activeAlert = .rename
                            },
                            onLeave: {
                                model.leaveGroup(group, authStateManager: authStateManager)
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
            }
            Section {
                Button {
                    model.activeAlert = .create
                } label: {
                    Label("Create Group", systemImage: "plus.circle")
                }
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
                model.joinGroup(authStateManager: authStateManager)
            }
        case .rename:
            TextField("Group Name", text: $model.renamedGroupName)
            Button("Cancel", role: .cancel) {
                model.groupToRename = nil
                model.renamedGroupName = ""
            }
            Button("Rename") {
                if let group = model.groupToRename {
                    model.renameGroup(group: group, newName: model.renamedGroupName, authStateManager: authStateManager)
                }
            }
        case .create:
            TextField("Group Name", text: $model.createdGroupName)
            Button("Cancel", role: .cancel) {
                model.createdGroupName = ""
            }
            Button("Create") {
                if !model.createdGroupName.isEmpty {
                    model.createGroup(authStateManager: authStateManager)
                }
            }
        case .inviteCode:
            Button("Copy Code") {
                model.copyInviteCode()
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
    }
}
