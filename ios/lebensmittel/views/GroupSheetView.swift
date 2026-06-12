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
	@State private var joinCode = ""
	@State private var isShowingJoinCode = false
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
			List {
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

				if let activeGroup = groupModel.activeGroup {
					Section {
						VStack(alignment: .leading, spacing: 4) {
							Text(activeGroup.name)
								.font(.headline)
							Text(activeGroup.id)
								.font(.caption.monospaced())
								.foregroundStyle(.secondary)
						}
					} header: {
						Label("Current Group", systemImage: "rectangle.3.group")
					} footer: {
						Text("Manage the active group's categories and members.")
					}

					Section {
						if currentGroupCategories.isEmpty {
							Text("No categories yet. Add one below.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}

						ForEach(Array(currentGroupCategories.enumerated()), id: \.offset) { index, value in
							Text(value)
								.font(.subheadline)
								.swipeActions(edge: .trailing, allowsFullSwipe: false) {
									Button {
										groupItemEditor = GroupItemEditorContext(kind: .category, index: index, initialValue: value)
									} label: {
										Label("Edit", systemImage: "pencil")
									}
									.tint(.blue)

									Button(role: .destructive) {
										pendingGroupItemDeletion = PendingGroupItemDeletion(kind: .category, index: index, value: value)
									} label: {
										Label("Delete", systemImage: "trash")
									}
								}
						}
						.onMove { source, destination in
							var updated = currentGroupCategories
							updated.move(fromOffsets: source, toOffset: destination)
							Task {
								await groupModel.setCategories(updated)
							}
						}

						Button {
							groupItemEditor = GroupItemEditorContext(kind: .category, index: nil, initialValue: "")
						} label: {
							Label("Add Category", systemImage: "plus.circle.fill")
								.font(.subheadline.weight(.semibold))
						}
						.disabled(groupModel.isLoading)
					} header: {
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
					}

					Section {
						if currentGroupMembers.isEmpty {
							Text("No members yet. Add one below.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}

						ForEach(Array(currentGroupMembers.enumerated()), id: \.offset) { index, value in
							Text(value)
								.font(.subheadline)
								.swipeActions(edge: .trailing, allowsFullSwipe: false) {
									Button {
										groupItemEditor = GroupItemEditorContext(kind: .member, index: index, initialValue: value)
									} label: {
										Label("Edit", systemImage: "pencil")
									}
									.tint(.blue)

									Button(role: .destructive) {
										pendingGroupItemDeletion = PendingGroupItemDeletion(kind: .member, index: index, value: value)
									} label: {
										Label("Delete", systemImage: "trash")
									}
								}
						}

						Button {
							groupItemEditor = GroupItemEditorContext(kind: .member, index: nil, initialValue: "")
						} label: {
							Label("Add Member", systemImage: "plus.circle.fill")
								.font(.subheadline.weight(.semibold))
						}
						.disabled(groupModel.isLoading)
					} header: {
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
					}
				} else {
					Section {
						Text("No active group selected.")
							.foregroundStyle(.secondary)
					} header: {
						Label("Current Group", systemImage: "rectangle.3.group")
					}
				}

				Section {
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
				} header: {
					Text("Group Settings")
				}

				Section {
					if groupModel.knownGroups.isEmpty {
						Text("No saved groups yet.")
							.foregroundStyle(.secondary)
					} else {
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
							}
							.buttonStyle(.plain)
							.disabled(groupModel.isLoading)
						}
					}
					HStack(spacing: 12) {
						Button {
							joinCode = ""
							isShowingJoinCode = true
						} label: {
							Text("Join new group with Code")
						}
						VStack(alignment: .leading, spacing: 4) {
							Text("Create Group")
								.font(.subheadline.weight(.semibold))
							Text("The current-group section is live; creation UI is next.")
								.font(.footnote)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
					}
				} header: {
					Text("Known Groups")
				}
			}
			.listStyle(.insetGrouped)
			.environment(\.editMode, .constant(isReorderingCategories ? .active : .inactive))
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
		.alert("Join Group", isPresented: $isShowingJoinCode) {
			TextField("Paste join code", text: $joinCode)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
			Button("Join") {
				Task {
					await groupModel.joinGroup(id: joinCode)
					if groupModel.errorMessage == nil {
						joinCode = ""
					}
				}
			}
			Button("Cancel", role: .cancel) {
				joinCode = ""
			}
		} message: {
			Text("Enter the join code shared by your group.")
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
