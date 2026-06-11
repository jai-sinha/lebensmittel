//
//  GroupIDMenuView.swift
//  lebensmittel
//
//  Created by Jai Sinha on 06/08/26.
//

import SwiftUI

struct GroupIDMenuView: View {
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

	@State private var newGroupName = ""
	@State private var renamedGroupName = ""
	@State private var errorMessage: String?
	@State private var isLoading = false
	@State private var isReorderingCategories = false
	@State private var groupItemEditor: GroupItemEditorContext?
	@State private var pendingGroupItemDeletion: PendingGroupItemDeletion?

	private var activeGroup: AuthGroup? {
		groupModel.activeGroup
	}

	private var currentGroupCategories: [String] {
		normalizedGroupValues(activeGroup?.categories ?? [])
	}

	private var currentGroupMembers: [String] {
		normalizedGroupValues(activeGroup?.members ?? [])
	}



	private var canCreateGroup: Bool {
		!newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private var canRenameActiveGroup: Bool {
		activeGroup != nil && !renamedGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	private var deleteAlertTitle: String {
		pendingGroupItemDeletion?.title ?? "Delete Item"
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					if let errorMessage {
						InlineErrorCard(message: errorMessage)
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
				renamedGroupName = activeGroup?.name ?? ""
			}
			.onChange(of: groupModel.activeGroupId) { _, _ in
				renamedGroupName = activeGroup?.name ?? ""
				isReorderingCategories = false
			}
		}
		.sheet(item: $groupItemEditor) { editor in
			GroupItemEditorSheet(
				title: editor.title,
				placeholder: editor.kind.placeholder,
				submitTitle: editor.submitTitle,
				initialValue: editor.initialValue,
				isLoading: isLoading
			) { value in
				saveGroupItem(value, using: editor)
			}
		}
		.alert(
			deleteAlertTitle,
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
				deleteGroupItem(pending)
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
			if let activeGroup {
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
							CountBadge(count: currentGroupCategories.count)
							if currentGroupCategories.count > 1 {
								Button(isReorderingCategories ? "Done" : "Reorder") {
									isReorderingCategories.toggle()
								}
								.font(.caption.weight(.semibold))
								.disabled(isLoading)
							}
						}

						if currentGroupCategories.isEmpty {
							Text("No categories yet. Add one below.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}

						categoryManagementList
					}

					VStack(alignment: .leading, spacing: 10) {
						HStack(spacing: 8) {
							Label("Members", systemImage: "person.2")
								.font(.subheadline.weight(.semibold))
							Spacer()
							CountBadge(count: currentGroupMembers.count)
						}

						if currentGroupMembers.isEmpty {
							Text("No members yet. Add one below.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}

						memberManagementList
					}
				}
			} else {
				Text("No active group selected.")
					.foregroundStyle(.secondary)
			}
		}
	}

	private var categoryManagementList: some View {
		List {
			ForEach(Array(currentGroupCategories.enumerated()), id: \.offset) { index, category in
				GroupManagementValueRow(value: category)
					.swipeActions(edge: .trailing, allowsFullSwipe: false) {
						Button {
							groupItemEditor = GroupItemEditorContext(
								kind: .category,
								index: index,
								initialValue: category
							)
						} label: {
							Label("Edit", systemImage: "pencil")
						}
						.tint(.blue)

						Button(role: .destructive) {
							pendingGroupItemDeletion = PendingGroupItemDeletion(
								kind: .category,
								index: index,
								value: category
							)
						} label: {
							Label("Delete", systemImage: "trash")
						}
					}
			}
			.onMove(perform: moveCategories)

			Button {
				groupItemEditor = GroupItemEditorContext(kind: .category, index: nil, initialValue: "")
			} label: {
				GroupManagementAddRow(title: "Add Category")
			}
			.disabled(isLoading)
		}
		.environment(\.editMode, .constant(isReorderingCategories ? .active : .inactive))
		.listStyle(.plain)
		.scrollDisabled(true)
		.scrollContentBackground(.hidden)
		.background(Color(.secondarySystemGroupedBackground))
		.frame(height: listHeight(for: currentGroupCategories.count + 1))
		.clipShape(RoundedRectangle(cornerRadius: 14))
		.disabled(isLoading)
	}

	private var memberManagementList: some View {
		List {
			ForEach(Array(currentGroupMembers.enumerated()), id: \.offset) { index, member in
				GroupManagementValueRow(value: member)
					.swipeActions(edge: .trailing, allowsFullSwipe: false) {
						Button {
							groupItemEditor = GroupItemEditorContext(
								kind: .member,
								index: index,
								initialValue: member
							)
						} label: {
							Label("Edit", systemImage: "pencil")
						}
						.tint(.blue)

						Button(role: .destructive) {
							pendingGroupItemDeletion = PendingGroupItemDeletion(
								kind: .member,
								index: index,
								value: member
							)
						} label: {
							Label("Delete", systemImage: "trash")
						}
					}
			}

			Button {
				groupItemEditor = GroupItemEditorContext(kind: .member, index: nil, initialValue: "")
			} label: {
				GroupManagementAddRow(title: "Add Member")
			}
			.disabled(isLoading)
		}
		.listStyle(.plain)
		.scrollDisabled(true)
		.scrollContentBackground(.hidden)
		.background(Color(.secondarySystemGroupedBackground))
		.frame(height: listHeight(for: currentGroupMembers.count + 1))
		.clipShape(RoundedRectangle(cornerRadius: 14))
		.disabled(isLoading)
	}

	private var knownGroupsSection: some View {
		GroupCardSection(title: "Known Groups") {
			if groupModel.knownGroups.isEmpty {
				Text("No saved groups yet.")
					.foregroundStyle(.secondary)
			} else {
				VStack(spacing: 10) {
					HStack(spacing: 12) {
						PlaceholderSettingRow(
							title: "Join with Code",
							description: "We'll wire this into the saved-groups flow next."
						)
						PlaceholderSettingRow(
							title: "Create Group",
							description: "The current-group section is live; creation UI is next."
						)
					}
					ForEach(groupModel.knownGroups) { group in
						Button {
							switchToGroup(group)
						} label: {
							KnownGroupRow(group: group, isActive: group.id == groupModel.activeGroupId)
						}
						.buttonStyle(.plain)
						.disabled(isLoading)
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
						renameActiveGroup()
					} label: {
						actionLabel("Save Group Name")
					}
					.buttonStyle(.bordered)
					.disabled(isLoading || !canRenameActiveGroup)
				}

				Divider()

				PlaceholderSettingRow(
					title: "Join Code",
					description: "Copy/share join-code support is the next group-settings task."
				)
				PlaceholderSettingRow(
					title: "Leave Group",
					description: "Destructive leave/remove behavior still needs to be wired."
				)
			}
		}
	}

	@ViewBuilder
	private func actionLabel(_ title: String) -> some View {
		if isLoading {
			ProgressView()
				.frame(maxWidth: .infinity)
		} else {
			Text(title)
				.frame(maxWidth: .infinity)
		}
	}

	private func listHeight(for rowCount: Int) -> CGFloat {
		CGFloat(max(rowCount, 1)) * 52 + 8
	}

	private func normalizedGroupValues(_ values: [String]) -> [String] {
		values
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
	}

	private func containsDuplicate(
		_ candidate: String,
		in values: [String],
		excluding excludedIndex: Int? = nil
	) -> Bool {
		values.enumerated().contains { index, value in
			index != excludedIndex && value.localizedCaseInsensitiveCompare(candidate) == .orderedSame
		}
	}

	private func values(for kind: GroupItemKind) -> [String] {
		switch kind {
		case .category:
			currentGroupCategories
		case .member:
			currentGroupMembers
		}
	}

	private func saveGroupItem(_ value: String, using editor: GroupItemEditorContext) {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }

		var updatedValues = values(for: editor.kind)
		if let index = editor.index {
			guard updatedValues.indices.contains(index) else { return }
			if updatedValues[index].localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
				return
			}
			if containsDuplicate(trimmed, in: updatedValues, excluding: index) {
				errorMessage = "\(editor.kind.title) \"\(trimmed)\" already exists."
				return
			}
			updatedValues[index] = trimmed
		} else {
			if containsDuplicate(trimmed, in: updatedValues) {
				errorMessage = "\(editor.kind.title) \"\(trimmed)\" already exists."
				return
			}
			updatedValues.append(trimmed)
		}

		updateGroupValues(kind: editor.kind, values: updatedValues)
	}

	private func deleteGroupItem(_ pending: PendingGroupItemDeletion) {
		pendingGroupItemDeletion = nil
		var updatedValues = values(for: pending.kind)
		guard updatedValues.indices.contains(pending.index) else { return }
		updatedValues.remove(at: pending.index)
		updateGroupValues(kind: pending.kind, values: updatedValues)
	}

	private func moveCategories(from source: IndexSet, to destination: Int) {
		guard !isLoading else { return }
		var updatedCategories = currentGroupCategories
		updatedCategories.move(fromOffsets: source, toOffset: destination)
		updateGroupValues(kind: .category, values: updatedCategories)
	}

	private func updateGroupValues(kind: GroupItemKind, values: [String]) {
		guard !isLoading, let activeGroup else { return }
		let normalizedValues = normalizedGroupValues(values)
		errorMessage = nil

		Task {
			isLoading = true
			do {
				switch kind {
				case .category:
					try await groupModel.updateGroupCategories(
						id: activeGroup.id,
						categories: normalizedValues
					)
				case .member:
					try await groupModel.updateGroupMembers(
						id: activeGroup.id,
						members: normalizedValues
					)
				}
				if kind == .category, normalizedValues.count < 2 {
					isReorderingCategories = false
				}
			} catch {
				errorMessage = UserFacingError.message(for: error)
			}
			isLoading = false
		}
	}

	private func switchToGroup(_ group: AuthGroup) {
		guard !isLoading else { return }
		errorMessage = nil
		Task {
			isLoading = true
			groupModel.setActiveGroup(group)
			isLoading = false
		}
	}

	private func createGroup() {
		guard !isLoading else { return }
		let groupName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !groupName.isEmpty else { return }
		errorMessage = nil

		Task {
			isLoading = true
			do {
				try await groupModel.createGroup(name: groupName)
				newGroupName = ""
				renamedGroupName = activeGroup?.name ?? ""
			} catch {
				errorMessage = UserFacingError.message(for: error)
			}
			isLoading = false
		}
	}

	private func renameActiveGroup() {
		guard !isLoading, let activeGroup else { return }
		let newName = renamedGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !newName.isEmpty else { return }
		errorMessage = nil

		Task {
			isLoading = true
			do {
				try await groupModel.renameGroup(id: activeGroup.id, name: newName)
				renamedGroupName = groupModel.knownGroups.first(where: { $0.id == activeGroup.id })?.name ?? newName
			} catch {
				errorMessage = UserFacingError.message(for: error)
			}
			isLoading = false
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

private struct CountBadge: View {
	let count: Int

	var body: some View {
		Text("\(count)")
			.font(.caption.weight(.semibold))
			.foregroundStyle(.secondary)
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(Color(.tertiarySystemGroupedBackground))
			.clipShape(Capsule())
	}
}

private enum GroupItemKind: String {
	case category
	case member

	var title: String {
		switch self {
		case .category:
			"Category"
		case .member:
			"Member"
		}
	}

	var placeholder: String {
		switch self {
		case .category:
			"Category name"
		case .member:
			"Member name"
		}
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

private struct GroupManagementValueRow: View {
	let value: String

	var body: some View {
		Text(value)
			.font(.subheadline)
	}
}

private struct GroupManagementAddRow: View {
	let title: String

	var body: some View {
		Label(title, systemImage: "plus.circle.fill")
			.font(.subheadline.weight(.semibold))
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

private struct PlaceholderSettingRow: View {
	let title: String
	let description: String

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.font(.subheadline.weight(.semibold))
			Text(description)
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

private struct KnownGroupRow: View {
	let group: AuthGroup
	let isActive: Bool

	private var iconName: String {
		isActive ? "checkmark.circle.fill" : "circle"
	}

	private var iconColor: Color {
		isActive ? .accentColor : .secondary
	}

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: iconName)
				.foregroundStyle(iconColor)
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
}

private struct InlineErrorCard: View {
	let message: String

	var body: some View {
		Text(message)
			.font(.footnote)
			.foregroundStyle(.red)
			.padding(12)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(Color.red.opacity(0.08))
			.clipShape(RoundedRectangle(cornerRadius: 12))
	}
}
