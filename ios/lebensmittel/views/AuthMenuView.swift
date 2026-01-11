//
//  AuthMenuView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/08/26.
//

import SwiftUI

struct AuthMenuView: View {
    @Environment(AuthStateManager.self) var authStateManager

    @State private var joinCode: String = ""
    @State private var showingJoinAlert = false
    @State private var errorMessage: String?

    // Rename State
    @State private var groupToRename: AuthGroup?
    @State private var newGroupName: String = ""
    @State private var showingRenameAlert = false

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
                                newGroupName = group.name
                                showingRenameAlert = true
                            },
                            onLeave: {
                                leaveGroup(group)
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
                    showingJoinAlert = true
                } label: {
                    Label("Join Group", systemImage: "person.badge.plus")
                }
            }
        } label: {
            Image(systemName: "person.circle")
                .imageScale(.large)
        }
        .alert("Join Group", isPresented: $showingJoinAlert) {
            TextField("Group ID", text: $joinCode)
            Button("Cancel", role: .cancel) {
                joinCode = ""
            }
            Button("Join") {
                joinGroup()
            }
        } message: {
            Text("Enter the ID of the group you want to join.")
        }
        .alert("Rename Group", isPresented: $showingRenameAlert) {
            TextField("Group Name", text: $newGroupName)
            Button("Cancel", role: .cancel) {
                groupToRename = nil
                newGroupName = ""
            }
            Button("Rename") {
                if let group = groupToRename {
                    renameGroup(group, to: newGroupName)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
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
                    errorMessage = "Failed to switch group: \(error.localizedDescription)"
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
                    newGroupName = ""
                }
            } catch {
                 await MainActor.run {
                    errorMessage = "Failed to rename group: \(error.localizedDescription)"
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
                    errorMessage = "Failed to join group: \(error.localizedDescription)"
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
                    errorMessage = "Failed to leave group: \(error.localizedDescription)"
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

    var body: some View {
        Menu {
            Button("Switch to this group") {
                onSwitch()
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
                Label(group.name, systemImage: "checkmark")
            } else {
                Label(group.name, systemImage: "circle")
            }
        }
    }
}
