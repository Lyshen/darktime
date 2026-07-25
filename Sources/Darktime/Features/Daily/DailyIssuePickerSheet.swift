import SwiftUI

struct DailyIssuePickerSheet: View {
    @ObservedObject var model: DashboardModel
    let issues: [MatterSnapshot]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectId: String?
    @State private var newIssueText = ""
    @State private var errorMessage: String?

    init(model: DashboardModel, issues: [MatterSnapshot]) {
        self.model = model
        self.issues = issues
        _selectedProjectId = State(initialValue: model.projects.first?.id)
    }

    private var projectGroups: [DailyIssueProjectGroup] {
        let projectsByID = Dictionary(uniqueKeysWithValues: model.projects.map { ($0.id, $0) })
        return Dictionary(grouping: issues) { issue in
            issue.projectId ?? ""
        }
        .compactMap { projectId, issues in
            guard let project = projectsByID[projectId] else {
                return nil
            }
            return DailyIssueProjectGroup(
                project: project,
                issues: issues.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
        .sorted { left, right in
            left.project.title.localizedCaseInsensitiveCompare(right.project.title) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Issue")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text("Choose an existing project issue, or create one for today.")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
            }

            if projectGroups.isEmpty {
                DailyPickerEmptyLine(
                    title: "No open project issues",
                    detail: "Create one below."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(projectGroups) { group in
                            DailyIssuePickerGroup(
                                model: model,
                                group: group,
                                onPick: {
                                    dismiss()
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 260)
            }

            Divider().overlay(DTColor.line.opacity(0.7))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Picker("Project", selection: $selectedProjectId) {
                        ForEach(model.projects, id: \.id) { project in
                            Text(project.title).tag(Optional(project.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170, alignment: .leading)

                    TextField("New issue", text: $newIssueText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .regular, design: .default))

                    Button("Create") {
                        create()
                    }
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(DTColor.workspace)
    }

    private var canCreate: Bool {
        selectedProjectId != nil && !newIssueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        guard
            let selectedProjectId,
            let project = model.projects.first(where: { $0.id == selectedProjectId })
        else {
            return
        }

        let ok = model.createProjectIssueForToday(project, text: newIssueText)
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct DailyIssueProjectGroup: Identifiable {
    let project: ProjectSnapshot
    let issues: [MatterSnapshot]

    var id: String { project.id }
}

private struct DailyIssuePickerGroup: View {
    @ObservedObject var model: DashboardModel
    let group: DailyIssueProjectGroup
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.project.title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .lineLimit(1)

            VStack(spacing: 0) {
                ForEach(group.issues, id: \.id) { issue in
                    DailyIssuePickerRow(model: model, issue: issue, onPick: onPick)
                    if issue.id != group.issues.last?.id {
                        DailyHairline()
                    }
                }
            }
        }
    }
}

private struct DailyIssuePickerRow: View {
    @ObservedObject var model: DashboardModel
    let issue: MatterSnapshot
    let onPick: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            model.addIssueToDailyFocus(issue)
            onPick()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DTColor.dimmed)
                    .frame(width: 16)

                Text(issue.text)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Text(dailyPickerIssueKindText(issue.issueKind))
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.black.opacity(0.018) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct DailyPickerEmptyLine: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
            Text(detail)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func dailyPickerIssueKindText(_ kind: String?) -> String {
    switch kind {
    case "github_pr":
        return "github pr"
    case "github_issue":
        return "github issue"
    default:
        return "manual"
    }
}
