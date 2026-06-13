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

// MARK: - GroupManagementSheet

private struct GroupManagementSheet: View {
	@Environment(GroupModel.self) private var groupModel
	@Environment(\.dismiss) private var dismiss

	@State private var alertText = ""
	@State private var showJoinAlert = false
	@State private var showCreateAlert = false
	@State private var showRenameAlert = false
	@State private var showLeaveAlert = false
	@State private var groupItemEditor: GroupItemEditorContext?
	@State private var pendingDeletion: PendingGroupItemDeletion?

	// MARK: Computed properties

	private var activeGroup: AuthGroup? {
		groupModel.activeGroup
	}

	private var groupCategories: [String] {
		groupModel.normalizedGroupValues(activeGroup?.categories ?? [])
	}

	private var groupMembers: [String] {
		groupModel.normalizedGroupValues(activeGroup?.members ?? [])
	}

	// MARK: - Content sections

	@ViewBuilder
	private var errorBanner: some View {
		if let errorMessage = groupModel.errorMessage {
			Text(errorMessage)
				.font(.footnote)
				.foregroundStyle(.red)
				.padding(12)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.red.opacity(0.08))
				.clipShape(RoundedRectangle(cornerRadius: 12))
				.listRowInsets(EdgeInsets())
		}
	}

	@ViewBuilder
	private var categoriesSection: some View {
		listSection(
				headerLabel: "Categories",
				headerIcon: "tag",
				items: groupCategories,
				isReorderable: true,
				emptyMessage: "No categories yet. Add one below.",
				addLabel: "Add Category",
				editAction: { index, value in
					groupItemEditor = GroupItemEditorContext(kind: .category, index: index, initialValue: value)
				},
				addAction: {
					groupItemEditor = GroupItemEditorContext(kind: .category, index: nil, initialValue: "")
				},
				deleteAction: { index, value in
					pendingDeletion = PendingGroupItemDeletion(kind: .category, index: index, value: value)
				}
			)
	}

	@ViewBuilder
	private var membersSection: some View {
		listSection(
			headerLabel: "Members",
			headerIcon: "person.2",
			items: groupMembers,
			isReorderable: false,
			emptyMessage: "No members yet. Add one below.",
			addLabel: "Add Member",
			editAction: { index, value in
				groupItemEditor = GroupItemEditorContext(kind: .member, index: index, initialValue: value)
			},
			addAction: {
				groupItemEditor = GroupItemEditorContext(kind: .member, index: nil, initialValue: "")
			},
			deleteAction: { index, value in
				pendingDeletion = PendingGroupItemDeletion(kind: .member, index: index, value: value)
			}
		)
	}

	private func listSection(
		headerLabel: String,
		headerIcon: String,
		items: [String],
		isReorderable: Bool,
		emptyMessage: String,
		addLabel: String,
		editAction: @escaping (Int, String) -> Void,
		addAction: @escaping () -> Void,
		deleteAction: ((Int, String) -> Void)? = nil
	) -> some View {
		Section {
			if items.isEmpty {
				Text(emptyMessage)
					.font(.footnote)
					.foregroundStyle(.secondary)
			}

			if isReorderable {
				ForEach(Array(items.enumerated()), id: \.offset) { index, value in
					itemRow(
						index: index,
						value: value,
						isReorderable: isReorderable,
						editAction: editAction,
						deleteAction: deleteAction
					)
				}
				.onMove { source, destination in
					var updated = items
					updated.move(fromOffsets: source, toOffset: destination)
					Task {
						await groupModel.setCategories(updated)
					}
				}
			} else {
				ForEach(Array(items.enumerated()), id: \.offset) { index, value in
					itemRow(
						index: index,
						value: value,
						isReorderable: isReorderable,
						editAction: editAction,
						deleteAction: deleteAction
					)
				}
			}

			Button(action: addAction) {
				Label(addLabel, systemImage: "plus.circle.fill")
					.font(.subheadline.weight(.semibold))
			}
			.disabled(groupModel.isLoading)
		} header: {
			HStack(spacing: 8) {
				Label(headerLabel, systemImage: headerIcon)
					.font(.subheadline.weight(.semibold))
				Spacer()
				Text("\(items.count)")
					.font(.caption.weight(.semibold))
					.foregroundStyle(.secondary)
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(Color(.tertiarySystemGroupedBackground))
					.clipShape(Capsule())
			}
		}
	}

	@ViewBuilder
	private var groupsSection: some View {
		Section {
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
								.font(.headline)
							HStack {
								Text(group.id)
									.font(.caption.monospaced())
										.foregroundStyle(.secondary)
								Spacer()
								Button {
									UIPasteboard.general.string = group.id
								} label: {
									Image(systemName: "square.on.square")
										.font(.caption.monospaced())
								}
								.buttonStyle(.borderless)
								.foregroundStyle(.secondary)
							}
						}
						Spacer()
					}
				}
				.buttonStyle(.plain)
				.disabled(groupModel.isLoading)
			}
		} header: {
			Label("Groups", systemImage: "rectangle.3.group")
		}
	}

	@ViewBuilder
	private var noGroupSection: some View {
		Section {
			Text("No active group selected.")
				.foregroundStyle(.secondary)
		} header: {
			Label("Current Group", systemImage: "rectangle.3.group")
		}
	}

	@ViewBuilder
	private var controlsSection: some View {
		Section {
			if let activeGroup {
				Button {
					alertText = activeGroup.name
					showRenameAlert = true
				} label: {
					Text("Rename Current Group")
				}

				Button(role: .destructive) {
					showLeaveAlert = true
				} label: {
					Text("Leave Current Group")
				}
			}

			Button {
				alertText = ""
				showJoinAlert = true
			} label: {
				Text("Join Group")
			}

			Button {
				alertText = ""
				showCreateAlert = true
			} label: {
				Text("Create Group")
			}
		} header: {
			Label("Group Controls", systemImage: "person.2.badge.gearshape")
		}
	}

	// MARK: - Body

	var body: some View {
		NavigationStack {
			List {
				errorBanner

				if activeGroup != nil {
					groupsSection
					categoriesSection
					membersSection
				} else {
					noGroupSection
				}

				controlsSection
			}
			.listStyle(.insetGrouped)
			.navigationTitle("Groups")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button("Done") {
						dismiss()
					}
				}
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
			"Delete \(pendingDeletion?.kind.title ?? "Item")",
			isPresented: Binding(
				get: { pendingDeletion != nil },
				set: { if !$0 { pendingDeletion = nil } }
			),
			presenting: pendingDeletion
		) { pending in
			Button("Delete", role: .destructive) {
				Task {
					await groupModel.deleteGroupItem(at: pending.index, kind: pending.kind)
					pendingDeletion = nil
				}
			}
			Button("Cancel", role: .cancel) {
				pendingDeletion = nil
			}
		} message: { pending in
			Text(pending.message)
		}
		.alert("Join Group", isPresented: $showJoinAlert) {
			TextField("Paste join code", text: $alertText)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
			Button("Join") {
				Task {
					await groupModel.joinGroup(id: alertText)
					if groupModel.errorMessage == nil {
						alertText = ""
					}
				}
			}
			Button("Cancel", role: .cancel) {
				alertText = ""
			}
		} message: {
			Text("Enter the join code shared by your group.")
		}
		.alert("Create New Group", isPresented: $showCreateAlert) {
			TextField("Group name", text: $alertText)
				.autocorrectionDisabled()
			Button("Create") {
				Task {
					await groupModel.createGroup(name: alertText)
					alertText = ""
				}
			}
			Button("Cancel", role: .cancel) {
				alertText = ""
			}
		} message: {
			Text("Enter a name for the new group.")
		}
		.alert("Rename Group", isPresented: $showRenameAlert) {
			TextField("New name", text: $alertText)
				.autocorrectionDisabled()
			Button("Rename") {
				guard let activeGroup, !alertText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
				Task {
					await groupModel.renameGroup(id: activeGroup.id, name: alertText)
					alertText = ""
				}
			}
			Button("Cancel", role: .cancel) {
				alertText = ""
			}
		} message: {
			Text("Enter a new name for this group.")
		}
		.alert("Leave Group?", isPresented: $showLeaveAlert) {
			Button("Leave", role: .destructive) {
				guard let activeGroup else { return }
				Task {
					groupModel.leaveGroup(id: activeGroup.id)
				}
			}
			Button("Cancel", role: .cancel) { }
		} message: {
			Text("Are you sure you want to leave this group?")
		}
	}
}

// MARK: - Helper types

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

// MARK: - Row helpers

@ViewBuilder
private func itemRow(
	index: Int,
	value: String,
	isReorderable: Bool,
	editAction: @escaping (Int, String) -> Void,
	deleteAction: ((Int, String) -> Void)?
) -> some View {
	HStack {
		Text(value)
			.font(.subheadline)
		Spacer()
		if isReorderable {
			Image(systemName: "line.3.horizontal")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}
	.swipeActions(edge: .trailing) {
		Button {
			editAction(index, value)
		} label: {
			Label("Edit", systemImage: "pencil")
		}
		.tint(.blue)

		if let deleteAction {
			Button(role: .destructive) {
				deleteAction(index, value)
			} label: {
				Label("Delete", systemImage: "trash")
			}
		}
	}
}

// MARK: - GroupItemEditorSheet

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
					.onSubmit(submit)
				Spacer()
			}
			.padding(16)
			.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(submitTitle, action: submit)
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
