import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct AttentionWorkspace: View {
    @ObservedObject var model: DashboardModel
    @State private var mode: AttentionMode = .items
    @State private var lens: AttentionLens = .current
    @State private var timelineRange: AttentionTimelineRange = .thirtyDays

    private var visibleRepos: [LocalRepoSnapshot] {
        model.localRepoSnapshots.filter { lens.includes(repo: $0) }
    }

    private var visibleIssues: [MatterSnapshot] {
        switch lens {
        case .current:
            return model.issueMatters.filter { attentionIssueState(for: $0) == "open" }
        case .fading:
            return model.issueMatters.filter { attentionIssueState(for: $0) == "stale" }
        case .inactive:
            return []
        case .all:
            return model.issueMatters
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AttentionTopBar(
                model: model,
                mode: $mode,
                lens: $lens,
                timelineRange: $timelineRange
            )
            Divider().overlay(DTColor.line.opacity(0.7))

            switch mode {
            case .items:
                AttentionItemsView(
                    model: model,
                    lens: lens,
                    visibleRepos: visibleRepos,
                    visibleIssues: visibleIssues,
                    emptyTitle: emptyTitle,
                    emptyDetail: emptyDetail
                )
            case .timeline:
                AttentionTimelineWorkspace(
                    repos: model.localRepoSnapshots,
                    actions: model.actions,
                    range: timelineRange
                )
            }
        }
        .background(DTColor.workspace)
    }

    private var emptyTitle: String {
        switch lens {
        case .current: return "No active attention"
        case .fading: return "No fading items"
        case .inactive: return "No inactive projects"
        case .all: return "No issues or projects yet"
        }
    }

    private var emptyDetail: String {
        switch lens {
        case .current: return "Clear Inbox into issues, or add a local repo as a project."
        case .fading: return "Issues and projects show up here when they start to drift."
        case .inactive: return "Inactive projects stay out of sight until you choose to review them."
        case .all: return "Clear Inbox into issues, or add a local repo as a project."
        }
    }
}

private struct AttentionItemsView: View {
    @ObservedObject var model: DashboardModel
    let lens: AttentionLens
    let visibleRepos: [LocalRepoSnapshot]
    let visibleIssues: [MatterSnapshot]
    let emptyTitle: String
    let emptyDetail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if visibleRepos.isEmpty && visibleIssues.isEmpty {
                    EmptyStateLine(
                        systemImage: "scope",
                        title: emptyTitle,
                        detail: emptyDetail
                    )
                } else {
                    if !visibleRepos.isEmpty {
                        AttentionSectionTitle("Projects")
                        VStack(spacing: 0) {
                            ForEach(visibleRepos, id: \.project.id) { repo in
                                LocalRepoProjectRow(model: model, repo: repo, lens: lens)
                                if repo.project.id != visibleRepos.last?.project.id {
                                    AttentionHairline()
                                }
                            }
                        }
                    }

                    if !visibleIssues.isEmpty {
                        AttentionSectionTitle("Issues")
                        VStack(spacing: 0) {
                            ForEach(visibleIssues, id: \.id) { matter in
                                IssueRow(model: model, matter: matter)
                                if matter.id != visibleIssues.last?.id {
                                    AttentionHairline()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 42)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
    }
}

private struct AttentionTopBar: View {
    @ObservedObject var model: DashboardModel
    @Binding var mode: AttentionMode
    @Binding var lens: AttentionLens
    @Binding var timelineRange: AttentionTimelineRange

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Attention")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Spacer()
            ProjectActionSyncStatus(model: model)
            AttentionModeSwitch(selection: $mode)
            if mode == .items {
                AttentionLensMenu(selection: $lens)
            } else {
                AttentionTimelineRangePicker(selection: $timelineRange)
            }
            QuietHeaderButton("Add Repo") {
                model.addLocalRepoProject()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private struct ProjectActionSyncStatus: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        if shouldShow {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .regular, design: .default))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.055), lineWidth: 1)
            )
            .help(helpText)
        }
    }

    private var shouldShow: Bool {
        model.isSyncingActions ||
            model.actionSyncError != nil ||
            model.actionSyncLastFinishedAt != nil ||
            !model.localRepoSnapshots.isEmpty
    }

    private var label: String {
        if model.isSyncingActions {
            return "Syncing"
        }
        if model.actionSyncError != nil {
            return "Sync failed"
        }
        if let lastFinishedAt = model.actionSyncLastFinishedAt {
            return "Synced \(formatRelative(lastFinishedAt))"
        }
        return "Not synced"
    }

    private var helpText: String {
        if let error = model.actionSyncError {
            return error
        }
        if model.isSyncingActions {
            return "Syncing local git actions."
        }
        if let lastFinishedAt = model.actionSyncLastFinishedAt {
            return "Last sync \(formatLocalDateTime(lastFinishedAt)). \(model.actionSyncLastChangeCount) actions changed."
        }
        return "Local git actions have not synced yet."
    }

    private var systemImage: String {
        if model.isSyncingActions {
            return "arrow.triangle.2.circlepath"
        }
        if model.actionSyncError != nil {
            return "exclamationmark.triangle"
        }
        return "checkmark.circle"
    }

    private var tint: Color {
        if model.isSyncingActions {
            return DTColor.cyan
        }
        if model.actionSyncError != nil {
            return DTColor.amber
        }
        return DTColor.dimmed
    }
}

private enum AttentionMode: String, CaseIterable, Identifiable {
    case items = "Items"
    case timeline = "Timeline"

    var id: String { rawValue }
}

private enum AttentionLens: String, CaseIterable, Identifiable {
    case current = "Current"
    case fading = "Fading"
    case inactive = "Inactive"
    case all = "All"

    var id: String { rawValue }

    func includes(repo: LocalRepoSnapshot) -> Bool {
        switch self {
        case .current:
            return repo.state == "alive" || repo.state == "quiet" || repo.state == "empty"
        case .fading:
            return repo.state == "fading"
        case .inactive:
            return repo.state == "inactive"
        case .all:
            return true
        }
    }
}

private struct AttentionModeSwitch: View {
    @Binding var selection: AttentionMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AttentionMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(selection == mode ? DTColor.text : DTColor.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selection == mode ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.045))
        )
    }
}

private struct AttentionLensMenu: View {
    @Binding var selection: AttentionLens

    var body: some View {
        Menu {
            ForEach(AttentionLens.allCases) { lens in
                Button {
                    selection = lens
                } label: {
                    if selection == lens {
                        Label(lens.rawValue, systemImage: "checkmark")
                    } else {
                        Text(lens.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .regular))
            }
            .foregroundStyle(DTColor.text)
            .frame(width: 28, height: 25)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct AttentionSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(DTColor.dimmed)
        .padding(.bottom, 2)
    }
}

private struct LocalRepoProjectRow: View {
    @ObservedObject var model: DashboardModel
    let repo: LocalRepoSnapshot
    let lens: AttentionLens
    @State private var isRowHovering = false
    @State private var isTitleHovering = false
    @State private var isEditing = false
    @State private var isCreatingIssue = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(stateTint)
                .frame(width: 28, height: 28)
                .background(stateTint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        model.openLocalRepo(repo)
                    } label: {
                        Text(repo.project.title)
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundStyle(DTColor.text)
                            .underline(isTitleHovering, color: DTColor.text.opacity(0.45))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(2)
                    .onHover { hovering in
                        isTitleHovering = hovering
                    }

                    if let intentionText {
                        Text(intentionText)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.text.opacity(0.5))
                            .lineLimit(1)
                    }

                    if repo.openIssueCount > 0 {
                        Text("\(repo.openIssueCount) issues")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.dimmed)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    Spacer(minLength: 8)
                }

                Text(repo.latestCommitSummary ?? "No commits yet")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
                    .lineLimit(2)

                HStack {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        ProjectActivityMetaGroup(
                            time: timeSummary,
                            count: commitWindowSummary,
                            state: repo.state,
                            tint: stateTint
                        )
                        .opacity(isRowHovering ? 0 : 1)

                        HStack(spacing: 2) {
                            AttentionRowActionButton("Issue") {
                                isCreatingIssue = true
                            }
                            AttentionRowActionButton("Edit") {
                                isEditing = true
                            }
                            AttentionRowActionButton("Remove") {
                                isConfirmingRemoval = true
                            }
                        }
                        .opacity(isRowHovering ? 1 : 0)
                        .allowsHitTesting(isRowHovering)
                    }
                    .animation(.easeOut(duration: 0.12), value: isRowHovering)
                }
                .frame(height: 19)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { hovering in
            isRowHovering = hovering
        }
        .sheet(isPresented: $isEditing) {
            ProjectEditSheet(model: model, project: repo.project)
        }
        .sheet(isPresented: $isCreatingIssue) {
            ProjectIssueCreateSheet(model: model, project: repo.project)
        }
        .alert("Remove project?", isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive) {
                model.removeProject(repo.project)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will not delete the local repository.")
        }
    }

    private var intentionText: String? {
        guard let intention = repo.project.intention?.trimmingCharacters(in: .whitespacesAndNewlines), !intention.isEmpty else {
            return nil
        }
        return intention
    }

    private var stateTint: Color {
        switch repo.state {
        case "alive": return DTColor.green
        case "quiet": return DTColor.cyan
        case "fading": return DTColor.amber
        case "inactive": return DTColor.dimmed
        case "empty": return DTColor.amber
        default: return DTColor.red
        }
    }

    private var timeSummary: String {
        if let lastCommitAt = repo.lastCommitAt {
            return formatAttentionTime(lastCommitAt, lens: lens)
        }
        return "no commits"
    }

    private var commitWindowSummary: String {
        switch repo.state {
        case "alive":
            return "\(repo.commitsLast2Days) in 2d"
        case "quiet":
            return "\(repo.commitsLast7Days) in 7d"
        case "fading", "inactive":
            return "\(repo.commitsLast30Days) in 30d"
        default:
            return "0 in 30d"
        }
    }
}

private struct ProjectIssueCreateSheet: View {
    @ObservedObject var model: DashboardModel
    let project: ProjectSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Issue")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(project.title)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .frame(height: 98)
                .padding(6)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func create() {
        let ok = model.createProjectIssue(project, text: text)
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct ProjectActivityMetaGroup: View {
    let time: String
    let count: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(time)
            Text("·")
                .foregroundStyle(DTColor.dimmed.opacity(0.75))
            Text(count)
            ProjectActivityTag(text: state, tint: tint)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }
}

private struct ProjectActivityTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold, design: .default))
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ProjectEditSheet: View {
    @ObservedObject var model: DashboardModel
    let project: ProjectSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var intention: String
    @State private var errorMessage: String?

    init(model: DashboardModel, project: ProjectSnapshot) {
        self.model = model
        self.project = project
        _title = State(initialValue: project.title)
        _intention = State(initialValue: project.intention ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Project")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(project.localPath ?? "")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .regular, design: .default))

                TextEditor(text: $intention)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .frame(height: 74)
                    .padding(6)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func save() {
        let ok = model.updateProject(
            project,
            title: title,
            intention: intention
        )
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct AttentionRowActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(isHovering ? DTColor.text.opacity(0.78) : DTColor.muted)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? Color.black.opacity(0.045) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct IssueRow: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var isAttaching = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(issueTint)
                .frame(width: 28, height: 28)
                .background(issueTint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(matter.text)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if let projectTitle = model.projectTitle(for: matter) {
                        Text(projectTitle)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.text.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }

                HStack {
                    IssueKindText(kind: matter.issueKind)
                    Spacer()
                }

                HStack {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        IssueActivityMetaGroup(
                            time: formatRelative(matter.updatedAt),
                            state: issueState,
                            tint: issueTint
                        )
                        .opacity(isHovering ? 0 : 1)

                        HStack(spacing: 2) {
                            AttentionRowActionButton("Edit") {
                                isEditing = true
                            }
                            if matter.projectId == nil {
                                AttentionRowActionButton("Attach") {
                                    isAttaching = true
                                }
                            } else {
                                AttentionRowActionButton("Detach") {
                                    model.detachIssue(matter)
                                }
                            }
                            AttentionRowActionButton("Make Project") {
                                model.linkIssueToLocalRepoProject(matter)
                            }
                            AttentionRowActionButton("Drop") {
                                model.moveMatter(matter, to: "dropped")
                            }
                        }
                        .opacity(isHovering ? 1 : 0)
                        .allowsHitTesting(isHovering)
                    }
                    .animation(.easeOut(duration: 0.12), value: isHovering)
                }
                .frame(height: 19)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .sheet(isPresented: $isEditing) {
            IssueEditSheet(model: model, issue: matter)
        }
        .sheet(isPresented: $isAttaching) {
            IssueProjectAttachSheet(model: model, issue: matter)
        }
    }

    private var issueState: String {
        attentionIssueState(for: matter)
    }

    private var issueTint: Color {
        issueState == "stale" ? DTColor.dimmed : DTColor.amber
    }

}

private struct IssueKindText: View {
    let kind: String?

    var body: some View {
        Text(displayKind)
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(DTColor.dimmed)
    }

    private var displayKind: String {
        switch kind {
        case "github_pr":
            return "github pr"
        case "github_issue":
            return "github issue"
        default:
            return "manual"
        }
    }
}

private struct IssueProjectAttachSheet: View {
    @ObservedObject var model: DashboardModel
    let issue: MatterSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectId: String?
    @State private var errorMessage: String?

    init(model: DashboardModel, issue: MatterSnapshot) {
        self.model = model
        self.issue = issue
        _selectedProjectId = State(initialValue: model.projects.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Attach Issue")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(issue.text)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(2)
            }

            Picker("Project", selection: $selectedProjectId) {
                ForEach(model.projects, id: \.id) { project in
                    Text(project.title).tag(Optional(project.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Attach") {
                    attach()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProjectId == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func attach() {
        guard
            let selectedProjectId,
            let project = model.projects.first(where: { $0.id == selectedProjectId })
        else {
            return
        }

        let ok = model.attachIssue(issue, to: project)
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct IssueEditSheet: View {
    @ObservedObject var model: DashboardModel
    let issue: MatterSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?

    init(model: DashboardModel, issue: MatterSnapshot) {
        self.model = model
        self.issue = issue
        _text = State(initialValue: issue.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Issue")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text("Keep the wording clear enough to return to it.")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .frame(height: 120)
                .padding(6)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func save() {
        let ok = model.updateIssue(issue, text: text)
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct IssueActivityMetaGroup: View {
    let time: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(time)
            Text("·")
                .foregroundStyle(DTColor.dimmed.opacity(0.75))
            ProjectActivityTag(text: state, tint: tint)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }
}

private func attentionIssueState(for matter: MatterSnapshot) -> String {
    guard let date = parseISODate(matter.updatedAt) else {
        return "open"
    }
    return Date().timeIntervalSince(date) > 7 * 86_400 ? "stale" : "open"
}

private func formatAttentionTime(_ isoString: String, lens: AttentionLens) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    if lens == .current || Calendar.current.isDateInToday(date) {
        return formatAttentionRelative(date)
    }

    let days = max(1, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 1)
    return "\(days)d ago · \(formatAttentionMonthDay(date))"
}

private func formatAttentionRelative(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 {
        return "now"
    }
    if seconds < 3600 {
        return "\(seconds / 60)m ago"
    }
    if seconds < 86_400 {
        return "\(seconds / 3600)h ago"
    }

    let days = max(1, seconds / 86_400)
    return "\(days)d ago"
}

private func formatAttentionMonthDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

private struct AttentionHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(height: 1)
    }
}
