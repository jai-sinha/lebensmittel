//
//  AuthMenuView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/08/26.
//

import SwiftUI

enum ActiveAlert: Equatable {
    case join
    case rename
    case create
    case inviteCode
    case error(String)

    var title: String {
        switch self {
        case .join: "Join Group"
        case .rename: "Rename Group"
        case .create: "Create Group"
        case .inviteCode: "Invite Code"
        case .error: "Error"
        }
    }
}

struct AuthMenuView: View {
    @Environment(AuthStateManager.self) var authStateManager

    @State private var joinCode: String = ""
    @State private var errorMessage: String?

    @State private var createdGroupName: String = ""

    @State private var inviteCode = ""

    // Rename State
    @State private var groupToRename: AuthGroup?
    @State private var renamedGroupName: String = ""

    @State private var activeAlert: ActiveAlert?

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
                                switchGroup(to: group.id)
                            },
                            onRename: {
                                groupToRename = group
                                renamedGroupName = group.name
                                activeAlert = .rename
                            },
                            onLeave: {
                                leaveGroup(group)
                            },
                            onInvite: {
                            	getGroupInviteCode(group)
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
                    activeAlert = .join
                } label: {
                    Label("Join Group", systemImage: "person.badge.plus")
                }
            }
            Section {
                Button {
                    activeAlert = .create
                } label: {
                    Label("Create Group", systemImage: "plus.circle")
                }
            }
        } label: {
            Image(systemName: "person.circle")
                .imageScale(.large)
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: Binding(
                get: { activeAlert != nil },
                set: { if !$0 { activeAlert = nil } }
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
        switch activeAlert {
        case .join:
            TextField("Invite Code", text: $joinCode)
            Button("Cancel", role: .cancel) {
                joinCode = ""
            }
            Button("Join") {
                joinGroup()
            }
        case .rename:
            TextField("Group Name", text: $renamedGroupName)
            Button("Cancel", role: .cancel) {
                groupToRename = nil
                renamedGroupName = ""
            }
            Button("Rename") {
                if let group = groupToRename {
                    renameGroup(group, to: renamedGroupName)
                }
            }
        case .create:
            TextField("Group Name", text: $createdGroupName)
            Button("Cancel", role: .cancel) {
                createdGroupName = ""
            }
            Button("Create") {
                if !createdGroupName.isEmpty {
                    createGroup()
                }
            }
        case .inviteCode:
            Button("Copy Code") {
                UIPasteboard.general.string = inviteCode
                inviteCode = ""
            }
            Button("OK", role: .cancel) {
                inviteCode = ""
            }
        case .error:
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func alertMessage() -> some View {
        switch activeAlert {
        case .join:
            Text("Enter the code for the group you want to join.")
        case .error(let message):
            Text(message)
        case .inviteCode:
            Text("Your invite code is: \(inviteCode)")
        default:
            EmptyView()
        }
    }

    // MARK: - Actions

    private func switchGroup(to groupId: String) {
        Task {
            do {
                try await AuthManager.shared.setActiveGroup(groupId)
                // Post notification to let other views know they should refresh data
                NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
                loadGroupData()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    activeAlert = .error(errorMessage ?? "Unknown error")
                }
            }
        }
    }

    private func renameGroup(_ group: AuthGroup, to newName: String) {
        Task {
            do {
                try await AuthManager.shared.renameGroup(groupId: group.id, newName: newName)
                loadGroupData()
                await MainActor.run {
                    groupToRename = nil
                    renamedGroupName = ""
                }
            } catch {
                 await MainActor.run {
                    errorMessage = error.localizedDescription
                    activeAlert = .error(errorMessage ?? "Unknown error")
                }
            }
        }
    }

    private func joinGroup() {
        guard !joinCode.isEmpty else { return }

        Task {
            do {
                try await AuthManager.shared.joinGroup(groupId: joinCode)
                await MainActor.run {
                    joinCode = ""
                }
                loadGroupData()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    activeAlert = .error(errorMessage ?? "Unknown error")
                }
            }
        }
    }

    private func getGroupInviteCode(_ group: AuthGroup) {
        Task {
            do {
                let code = try await AuthManager.shared.getGroupInviteCode(groupId: group.id)
                await MainActor.run {
                    inviteCode = code
                    activeAlert = .inviteCode
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    activeAlert = .error(errorMessage ?? "Unknown error")
                }
            }
        }
    }

    private func createGroup() {
        guard !createdGroupName.isEmpty else { return }
        Task {
            do {
                try await AuthManager.shared.createGroup(groupName: createdGroupName)
                await MainActor.run {
                    createdGroupName = ""
                }
                loadGroupData()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    activeAlert = .error(errorMessage ?? "Unknown error")
                }
            }
        }

    }

    private func leaveGroup(_ group: AuthGroup) {
        Task {
            do {
                try await AuthManager.shared.leaveGroup(groupId: group.id)
                // If we left the active group, clear it
                if authStateManager.currentUserActiveGroupId == group.id {
                     try await AuthManager.shared.setActiveGroup("")
                     // Notify change
                     NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
                }
                loadGroupData()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    activeAlert = .error(errorMessage ?? "Unknown error")
                }
            }
        }
    }

    private func loadGroupData() {
        authStateManager.checkAuthentication()
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
                Text(group.name)
                    .fontWeight(.bold)
            } else {
                Text(group.name)
            }
        }
    }
}
