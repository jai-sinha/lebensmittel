//
//  GroupSheetView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 06/08/26.
//

import SwiftUI

struct GroupSheetView: View {
	@Environment(GroupModel.self) private var groupModel
	@State private var isSheetPresented = false

	var body: some View {
		Button {
			isSheetPresented = true
		} label: {
			Image(systemName: "ellipsis.circle")
				.imageScale(.large)
		}
		.sheet(isPresented: $isSheetPresented) {
			GroupManagementSheet()
				.environment(groupModel)
		}
	}
}

private struct GroupManagementSheet: View {
	@Environment(GroupModel.self) private var groupModel
	@Environment(\.dismiss) private var dismiss

	@State private var renamedGroupName = ""
	@State private var isReorderingCategories = false
	@State private var groupItemEditor: GroupItemEditorContext?
	@State private var pendingGroupItemDeletion: PendingGroupItemDeletion?

	private var currentGroupCategories: [String] {
		groupModel.normalizedGroupValues(groupModel.activeGroup?.categories ?? [])
	}

	private var currentGroupMembers: [String] {
		groupModel.normalizedGroupValues(groupModel.activeGroup?.members ?? [])
	}

	private var canRenameActiveGroup: Bool {
		groupModel.activeGroup != nil && !renamedGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					if let errorMessage = groupModel.errorMessage {
						Text(errorMessage)
							.font(.footnote)
							.foregroundStyle(.red)
							.padding(12)
							.frame(maxWidth: .infinity, alignment: .leading)
							.background(Color.red.opacity(0.08))
							.clipShape(RoundedRectangle(cornerRadius: 12))
					}
					currentGroupSection
					groupSettingsSection
					knownGroupsSection
				}
				.padding(16)
			}
			.background(Color(.systemGroupedBackground))
			.navigationTitle("Groups")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button("Done") {
						dismiss()
					}
				}
			}
			.onAppear {
				renamedGroupName = groupModel.activeGroup?.name ?? ""
			}
			.onChange(of: groupModel.activeGroupId) { _, _ in
				renamedGroupName = groupModel.activeGroup?.name ?? ""
				isReorderingCategories = false
			}
		}
		.sheet(item: $groupItemEditor) { editor in
			GroupItemEditorSheet(
				title: editor.title,
				placeholder: editor.kind.placeholder,
				submitTitle: editor.submitTitle,
				initialValue: editor.initialValue,
				isLoading: groupModel.isLoading
			) { value in
				Task {
					await groupModel.saveGroupItem(value: value, kind: editor.kind, index: editor.index)
				}
			}
		}
		.alert(
			pendingGroupItemDeletion?.title ?? "Delete Item",
			isPresented: Binding(
				get: { pendingGroupItemDeletion != nil },
				set: { isPresented in
					if !isPresented {
						pendingGroupItemDeletion = nil
					}
				}
			),
			presenting: pendingGroupItemDeletion
		) { pending in
			Button("Delete", role: .destructive) {
				Task {
					await groupModel.deleteGroupItem(at: pending.index, kind: pending.kind)
					pendingGroupItemDeletion = nil
				}
			}
			Button("Cancel", role: .cancel) {
				pendingGroupItemDeletion = nil
			}
		} message: { pending in
			Text(pending.message)
		}
	}

	private var currentGroupSection: some View {
		GroupCardSection(
			title: "Current Group",
			subtitle: "Manage the active group's categories and members."
		) {
			if let activeGroup = groupModel.activeGroup {
				VStack(alignment: .leading, spacing: 16) {
					VStack(alignment: .leading, spacing: 4) {
						Text(activeGroup.name)
							.font(.headline)
						Text(activeGroup.id)
							.font(.caption.monospaced())
							.foregroundStyle(.secondary)
					}

					VStack(alignment: .leading, spacing: 10) {
						HStack(spacing: 8) {
							Label("Categories", systemImage: "tag")
								.font(.subheadline.weight(.semibold))
							Spacer()
							Text("\(currentGroupCategories.count)")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.background(Color(.tertiarySystemGroupedBackground))
								.clipShape(Capsule())
							if currentGroupCategories.count > 1 {
								Button(isReorderingCategories ? "Done" : "Reorder") {
									isReorderingCategories.toggle()
								}
								.font(.caption.weight(.semibold))
								.disabled(groupModel.isLoading)
							}
						}

						if currentGroupCategories.isEmpty {
							Text("No categories yet. Add one below.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}

						itemManagementList(kind: .category, values: currentGroupCategories, addTitle: "Add Category")
					}

					VStack(alignment: .leading, spacing: 10) {
						HStack(spacing: 8) {
							Label("Members", systemImage: "person.2")
								.font(.subheadline.weight(.semibold))
							Spacer()
							Text("\(currentGroupMembers.count)")
								.font(.caption.weight(.semibold))
								.foregroundStyle(.secondary)
								.padding(.horizontal, 8)
								.padding(.vertical, 4)
								.background(Color(.tertiarySystemGroupedBackground))
								.clipShape(Capsule())
						}

						if currentGroupMembers.isEmpty {
							Text("No members yet. Add one below.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}

						itemManagementList(kind: .member, values: currentGroupMembers, addTitle: "Add Member")
					}
				}
			} else {
				Text("No active group selected.")
					.foregroundStyle(.secondary)
			}
		}
	}

	private func itemManagementList(kind: GroupItemKind, values: [String], addTitle: String) -> some View {
		List {
			ForEach(Array(values.enumerated()), id: \.offset) { index, value in
				Text(value)
					.font(.subheadline)
					.swipeActions(edge: .trailing, allowsFullSwipe: false) {
						Button {
							groupItemEditor = GroupItemEditorContext(kind: kind, index: index, initialValue: value)
						} label: {
							Label("Edit", systemImage: "pencil")
						}
						.tint(.blue)

						Button(role: .destructive) {
							pendingGroupItemDeletion = PendingGroupItemDeletion(kind: kind, index: index, value: value)
						} label: {
							Label("Delete", systemImage: "trash")
						}
					}
			}
			.onMove { source, destination in
				Task {
					await groupModel.moveCategories(from: source, to: destination)
				}
			}

			Button {
				groupItemEditor = GroupItemEditorContext(kind: kind, index: nil, initialValue: "")
			} label: {
				Label(addTitle, systemImage: "plus.circle.fill")
					.font(.subheadline.weight(.semibold))
			}
			.disabled(groupModel.isLoading)
		}
		.environment(\.editMode, .constant(kind == .category && isReorderingCategories ? .active : .inactive))
		.listStyle(.plain)
		.scrollDisabled(true)
		.scrollContentBackground(.hidden)
		.background(Color(.secondarySystemGroupedBackground))
		.frame(height: CGFloat(max(values.count + 1, 1)) * 52 + 8)
		.clipShape(RoundedRectangle(cornerRadius: 14))
		.disabled(groupModel.isLoading)
	}

	private var knownGroupsSection: some View {
		GroupCardSection(title: "Known Groups") {
			if groupModel.knownGroups.isEmpty {
				Text("No saved groups yet.")
					.foregroundStyle(.secondary)
			} else {
				VStack(spacing: 10) {
					HStack(spacing: 12) {
						VStack(alignment: .leading, spacing: 4) {
							Text("Join with Code")
								.font(.subheadline.weight(.semibold))
							Text("We'll wire this into the saved-groups flow next.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
						VStack(alignment: .leading, spacing: 4) {
							Text("Create Group")
								.font(.subheadline.weight(.semibold))
							Text("The current-group section is live; creation UI is next.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					}
					ForEach(groupModel.knownGroups) { group in
						Button {
							Task {
								await groupModel.switchToGroup(group)
							}
						} label: {
							HStack(spacing: 12) {
								Image(systemName: group.id == groupModel.activeGroupId ? "checkmark.circle.fill" : "circle")
									.foregroundStyle(group.id == groupModel.activeGroupId ? Color.accentColor : Color.secondary)
								VStack(alignment: .leading, spacing: 2) {
									Text(group.name)
										.foregroundStyle(.primary)
									Text(group.id)
										.font(.caption.monospaced())
										.foregroundStyle(.secondary)
								}
								Spacer()
							}
							.padding(12)
							.background(Color(.secondarySystemGroupedBackground))
							.clipShape(RoundedRectangle(cornerRadius: 12))
						}
						.buttonStyle(.plain)
						.disabled(groupModel.isLoading)
					}
				}
			}
		}
	}

	private var groupSettingsSection: some View {
		GroupCardSection(title: "Group Settings") {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 8) {
					Text("Group Name")
						.font(.subheadline.weight(.semibold))
					TextField("Group Name", text: $renamedGroupName)
						.textFieldStyle(.roundedBorder)

					Button {
						Task {
							guard let activeGroup = groupModel.activeGroup else { return }
							await groupModel.renameGroup(id: activeGroup.id, name: renamedGroupName)
							if groupModel.errorMessage == nil {
								renamedGroupName = groupModel.activeGroup?.name ?? renamedGroupName
							}
						}
					} label: {
						if groupModel.isLoading {
							ProgressView()
								.frame(maxWidth: .infinity)
						} else {
							Text("Save Group Name")
								.frame(maxWidth: .infinity)
						}
					}
					.buttonStyle(.bordered)
					.disabled(groupModel.isLoading || !canRenameActiveGroup)
				}

				Divider()

				VStack(alignment: .leading, spacing: 4) {
					Text("Join Code")
						.font(.subheadline.weight(.semibold))
					Text("Copy/share join-code support is the next group-settings task.")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				VStack(alignment: .leading, spacing: 4) {
					Text("Leave Group")
						.font(.subheadline.weight(.semibold))
					Text("Destructive leave/remove behavior still needs to be wired.")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
	}

}

private struct GroupCardSection<Content: View>: View {
	let title: String
	let subtitle: String?
	private let content: Content

	init(
		title: String,
		subtitle: String? = nil,
		@ViewBuilder content: () -> Content
	) {
		self.title = title
		self.subtitle = subtitle
		self.content = content()
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(title)
				.font(.headline)
			if let subtitle {
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			content
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color(.systemBackground))
		.clipShape(RoundedRectangle(cornerRadius: 18))
	}
}

private struct GroupItemEditorContext: Identifiable {
	let kind: GroupItemKind
	let index: Int?
	let initialValue: String

	var id: String {
		"\(kind.rawValue)-\(index.map(String.init) ?? "new")"
	}

	var title: String {
		index == nil ? "Add \(kind.title)" : "Edit \(kind.title)"
	}

	var submitTitle: String {
		index == nil ? "Add" : "Save"
	}
}

private struct PendingGroupItemDeletion: Identifiable {
	let kind: GroupItemKind
	let index: Int
	let value: String

	var id: String {
		"\(kind.rawValue)-\(index)-\(value)"
	}

	var title: String {
		"Delete \(kind.title)"
	}

	var message: String {
		"Remove \"\(value)\" from this group?"
	}
}

private struct GroupItemEditorSheet: View {
	let title: String
	let placeholder: String
	let submitTitle: String
	let initialValue: String
	let isLoading: Bool
	let onSave: (String) -> Void

	@Environment(\.dismiss) private var dismiss
	@FocusState private var isTextFieldFocused: Bool
	@State private var value: String

	init(
		title: String,
		placeholder: String,
		submitTitle: String,
		initialValue: String,
		isLoading: Bool,
		onSave: @escaping (String) -> Void
	) {
		self.title = title
		self.placeholder = placeholder
		self.submitTitle = submitTitle
		self.initialValue = initialValue
		self.isLoading = isLoading
		self.onSave = onSave
		_value = State(initialValue: initialValue)
	}

	private var canSubmit: Bool {
		!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
	}

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 16) {
				TextField(placeholder, text: $value)
					.textFieldStyle(.roundedBorder)
					.focused($isTextFieldFocused)
					.onSubmit {
						submit()
					}

				Spacer()
			}
			.padding(16)
			.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						dismiss()
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(submitTitle) {
						submit()
					}
					.disabled(!canSubmit)
				}
			}
			.onAppear {
				isTextFieldFocused = true
			}
		}
	}

	private func submit() {
		guard canSubmit else { return }
		onSave(value)
		dismiss()
	}
}
