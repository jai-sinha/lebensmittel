//
//  AuthMenuView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 01/08/26.
//

import SwiftUI

struct AuthMenuView: View {
	@Environment(SessionManager.self) var sessionManager
	@State private var showGroupIDAlert = false
	@State private var groupIDInput = ""

	private var activeGroupId: String? {
		sessionManager.activeGroupId
	}

	var body: some View {
		Menu {
			Section("Current Group") {
				if let activeGroupId, !activeGroupId.isEmpty {
					Text(activeGroupId)
					Button("Copy Group ID") {
						UIPasteboard.general.string = activeGroupId
					}
				} else {
					Text("No group selected")
				}
			}

			Section {
				Button(activeGroupId == nil ? "Set Group ID" : "Change Group ID") {
					groupIDInput = activeGroupId ?? ""
					showGroupIDAlert = true
				}

				if activeGroupId != nil {
					Button("Clear Group ID", role: .destructive) {
						sessionManager.clearActiveGroup()
					}
				}
			}
		} label: {
			Image(systemName: "person.circle")
				.imageScale(.large)
		}
		.alert("Set Group ID", isPresented: $showGroupIDAlert) {
			TextField("Group ID", text: $groupIDInput)
			Button("Cancel", role: .cancel) {
				groupIDInput = activeGroupId ?? ""
			}
			Button("Save") {
				sessionManager.setActiveGroup(groupIDInput)
			}
		} message: {
			Text("Enter the group ID this device should use.")
		}
	}
}
