//
//  AuthMenuView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/08/26.
//

import SwiftUI

struct AuthMenuView: View {
    @Environment(AuthStateManager.self) var authStateManager

    @State private var groups: [AuthGroup] = []
    @State private var activeGroupId: String = ""
    @State private var joinCode: String = ""
    @State private var showingJoinAlert = false
    @State private var errorMessage: String?

    var body: some View {
        Menu {
            // MARK: - User Info
            if let user = authStateManager.currentUser {
                Text(user.displayName)
            }

            Button(role: .destructive) {
                authStateManager.logout()
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Divider()

            // MARK: - Group Selection
            if !groups.isEmpty {
                Picker("Current Group", selection: $activeGroupId) {
                    ForEach(groups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                .onChange(of: activeGroupId) { _, newValue in
                    if !newValue.isEmpty {
                        switchGroup(to: newValue)
                    }
                }
            } else {
                Text("No Groups Available")
            }

            Divider()

            // MARK: - Group Actions
            Button {
                showingJoinAlert = true
            } label: {
                Label("Join Group", systemImage: "person.badge.plus")
            }

            if !activeGroupId.isEmpty {
                Button(role: .destructive) {
                    leaveCurrentGroup()
                } label: {
                    Label("Leave Current Group", systemImage: "rectangle.portrait.and.arrow.right.fill")
                }
            }

        } label: {
            Image(systemName: "person.circle")
                .imageScale(.large)
        }
        .onAppear {
            loadGroupData()
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

    private func loadGroupData() {
        Task {
            do {
                // Fetch groups and active group in parallel
                async let groupsTask = AuthManager.shared.getUserGroups()
                async let activeGroupTask = AuthManager.shared.getActiveGroupId()

                let (fetchedGroups, fetchedActiveId) = try await (groupsTask, activeGroupTask)

                await MainActor.run {
                    self.groups = fetchedGroups
                    self.activeGroupId = fetchedActiveId

                    // If active group is not in list (edge case), default to first if available
                    if !fetchedActiveId.isEmpty && !fetchedGroups.contains(where: { $0.id == fetchedActiveId }) {
                        if let first = fetchedGroups.first {
                            self.activeGroupId = first.id
                            switchGroup(to: first.id)
                        }
                    }
                }
            } catch {
                print("Failed to load group data: \(error.localizedDescription)")
            }
        }
    }

    private func switchGroup(to groupId: String) {
        Task {
            do {
                try await AuthManager.shared.setActiveGroup(groupId)
                // Post notification to let other views know they should refresh data
                NotificationCenter.default.post(name: Notification.Name("GroupChanged"), object: nil)
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to switch group: \(error.localizedDescription)"
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

    private func leaveCurrentGroup() {
        guard !activeGroupId.isEmpty else { return }

        Task {
            do {
                try await AuthManager.shared.leaveGroup(groupId: activeGroupId)
                // Clear active group locally
                try await AuthManager.shared.setActiveGroup("")
                loadGroupData()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to leave group: \(error.localizedDescription)"
                }
            }
        }
    }
}
