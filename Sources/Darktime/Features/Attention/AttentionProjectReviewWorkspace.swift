import Foundation
import SwiftUI

enum ProjectReviewRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case sevenDays = "7D"
    case thirtyDays = "30D"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .sevenDays: return "7 days"
        case .thirtyDays: return "30 days"
        }
    }

    var startDate: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch self {
        case .today:
            return today
        case .sevenDays:
            return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .thirtyDays:
            return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        }
    }

    func contains(_ isoString: String) -> Bool {
        guard let date = parseISODate(isoString) else {
            return false
        }
        return date >= startDate && date <= Date()
    }
}

struct ProjectReviewRangePicker: View {
    @Binding var selection: ProjectReviewRange

    var body: some View {
        Menu {
            ForEach(ProjectReviewRange.allCases) { range in
                Button {
                    selection = range
                } label: {
                    if selection == range {
                        Label(range.title, systemImage: "checkmark")
                    } else {
                        Text(range.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
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
        .help("Review range: \(selection.title)")
    }
}

struct AttentionProjectReviewWorkspace: View {
    @ObservedObject var model: DashboardModel
    let repos: [LocalRepoSnapshot]
    let actions: [ActionSnapshot]
    let issues: [MatterSnapshot]
    let range: ProjectReviewRange

    private var rows: [ProjectReviewRowData] {
        projectReviewRows(repos: repos, actions: actions, issues: issues, range: range)
    }

    private var movedRows: [ProjectReviewRowData] {
        rows.filter(\.hasMovement)
    }

    private var waitingRows: [ProjectReviewRowData] {
        rows.filter { !$0.hasMovement && $0.hasOpenWork }
    }

    private var actionCount: Int {
        movedRows.reduce(0) { $0 + $1.actionCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if movedRows.isEmpty && waitingRows.isEmpty {
                    EmptyStateLine(
                        systemImage: "clock.arrow.circlepath",
                        title: "No review signal",
                        detail: "Actions and project issues will show up here when there is something to review."
                    )
                } else {
                    ProjectReviewSummaryLine(
                        range: range,
                        movedCount: movedRows.count,
                        waitingCount: waitingRows.count,
                        actionCount: actionCount
                    )

                    if !movedRows.isEmpty {
                        ProjectReviewSectionTitle("Moved Projects")
                        ProjectReviewRowList(model: model, rows: movedRows, rowKind: .moved)
                    }

                    if !waitingRows.isEmpty {
                        ProjectReviewSectionTitle("Waiting Projects")
                        ProjectReviewRowList(model: model, rows: waitingRows, rowKind: .waiting)
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

private enum ProjectReviewRowKind {
    case moved
    case waiting
}

private struct ProjectReviewRowData: Identifiable {
    let repo: LocalRepoSnapshot
    let linkedWork: [ProjectReviewWorkItem]
    let unlinkedActions: [ActionSnapshot]
    let waitingIssues: [MatterSnapshot]

    var id: String { repo.project.id }

    var latestAction: ActionSnapshot? {
        allActions.first
    }

    var allActions: [ActionSnapshot] {
        (linkedWork.flatMap(\.actions) + unlinkedActions)
            .sorted { $0.happenedAt > $1.happenedAt }
    }

    var actionCount: Int {
        allActions.count
    }

    var openWorkCount: Int {
        linkedWork.count + waitingIssues.count
    }

    var hasMovement: Bool {
        actionCount > 0
    }

    var hasOpenWork: Bool {
        openWorkCount > 0
    }
}

private struct ProjectReviewWorkItem: Identifiable {
    let issue: MatterSnapshot
    let actions: [ActionSnapshot]

    var id: String { issue.id }
}

private struct ProjectReviewSummaryLine: View {
    let range: ProjectReviewRange
    let movedCount: Int
    let waitingCount: Int
    let actionCount: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(range.title)
                .foregroundStyle(DTColor.text)
            Text("·")
                .foregroundStyle(DTColor.dimmed)
            Text("\(movedCount) moved")
            Text("·")
                .foregroundStyle(DTColor.dimmed)
            Text("\(waitingCount) waiting")
            Text("·")
                .foregroundStyle(DTColor.dimmed)
            Text(actionCount == 1 ? "1 action" : "\(actionCount) actions")
        }
        .font(.system(size: 12, weight: .regular, design: .default))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }
}

private struct ProjectReviewSectionTitle: View {
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

private struct ProjectReviewRowList: View {
    @ObservedObject var model: DashboardModel
    let rows: [ProjectReviewRowData]
    let rowKind: ProjectReviewRowKind

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                ProjectReviewRow(model: model, row: row, rowKind: rowKind)
                if row.id != rows.last?.id {
                    AttentionHairline()
                }
            }
        }
    }
}

private struct ProjectReviewRow: View {
    @ObservedObject var model: DashboardModel
    let row: ProjectReviewRowData
    let rowKind: ProjectReviewRowKind
    @State private var isTitleHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: rowKind == .moved ? "waveform.path.ecg" : "pause.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        model.openLocalRepo(row.repo)
                    } label: {
                        Text(row.repo.project.title)
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

                    Spacer(minLength: 8)

                    ProjectReviewMeta(row: row, tint: tint)
                }

                ProjectReviewWorkSections(model: model, row: row)
            }
        }
        .padding(.vertical, 13)
    }

    private var intentionText: String? {
        guard let intention = row.repo.project.intention?.trimmingCharacters(in: .whitespacesAndNewlines), !intention.isEmpty else {
            return nil
        }
        return intention
    }

    private var tint: Color {
        rowKind == .moved ? DTColor.green : DTColor.amber
    }
}

private struct ProjectReviewMeta: View {
    let row: ProjectReviewRowData
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(actionText)
            Text("·")
                .foregroundStyle(DTColor.dimmed.opacity(0.75))
            Text(issueText)
            ProjectActivityTag(text: stateText, tint: tint)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }

    private var actionText: String {
        let count = row.actionCount
        guard count > 0 else {
            return "no action"
        }
        let noun = count == 1 ? "action" : "actions"
        return "\(count) \(noun)"
    }

    private var issueText: String {
        let count = row.openWorkCount
        let noun = count == 1 ? "item" : "items"
        return "\(count) open \(noun)"
    }

    private var stateText: String {
        row.hasMovement ? "moved" : "waiting"
    }
}

private struct ProjectReviewWorkSections: View {
    @ObservedObject var model: DashboardModel
    let row: ProjectReviewRowData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !row.linkedWork.isEmpty {
                ProjectReviewGroupLabel("Linked work")
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(row.linkedWork.prefix(3))) { work in
                        ProjectReviewWorkItemLine(model: model, work: work)
                    }
                    if row.linkedWork.count > 3 {
                        ProjectReviewMoreLine(count: row.linkedWork.count - 3, noun: "more work items")
                    }
                }
            }

            if !row.unlinkedActions.isEmpty {
                ProjectReviewGroupLabel("Unlinked actions")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(row.unlinkedActions.prefix(3)), id: \.id) { action in
                        ProjectReviewActionLine(action: action)
                    }
                    if row.unlinkedActions.count > 3 {
                        ProjectReviewMoreLine(count: row.unlinkedActions.count - 3, noun: "more actions")
                    }
                }
            }

            if !row.waitingIssues.isEmpty {
                ProjectReviewGroupLabel("Waiting issues")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(row.waitingIssues.prefix(3)), id: \.id) { issue in
                        ProjectReviewIssueLine(model: model, issue: issue)
                    }
                    if row.waitingIssues.count > 3 {
                        ProjectReviewMoreLine(count: row.waitingIssues.count - 3, noun: "more issues")
                    }
                }
            }
        }
    }
}

private struct ProjectReviewGroupLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium, design: .default))
            .foregroundStyle(DTColor.dimmed)
            .padding(.top, 1)
    }
}

private struct ProjectReviewWorkItemLine: View {
    @ObservedObject var model: DashboardModel
    let work: ProjectReviewWorkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProjectReviewIssueLine(model: model, issue: work.issue, trailingText: actionCountText)
            if let latestAction = work.actions.first {
                ProjectReviewActionLine(action: latestAction, isSubtle: true)
                    .padding(.leading, 16)
            }
        }
    }

    private var actionCountText: String? {
        guard !work.actions.isEmpty else {
            return nil
        }
        let noun = work.actions.count == 1 ? "action" : "actions"
        return "\(work.actions.count) \(noun)"
    }
}

private struct ProjectReviewIssueLine: View {
    @ObservedObject var model: DashboardModel
    let issue: MatterSnapshot
    var trailingText: String? = nil

    var body: some View {
        if issue.externalUrl != nil {
            Button {
                model.openExternalIssue(issue)
            } label: {
                line
            }
            .buttonStyle(.plain)
        } else {
            line
        }
    }

    private var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(issueKind)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 54, alignment: .leading)
            Text(issue.text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text.opacity(0.72))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }
        }
    }

    private var issueKind: String {
        switch issue.issueKind {
        case "github_pr": return "pr"
        case "github_issue": return "gh"
        default: return "issue"
        }
    }
}

private struct ProjectReviewActionLine: View {
    let action: ActionSnapshot
    var isSubtle = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatReviewActionDate(action.happenedAt))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 54, alignment: .leading)
            Text(action.summary ?? "Action")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(isSubtle ? DTColor.dimmed : DTColor.muted)
                .lineLimit(1)
        }
    }
}

private struct ProjectReviewMoreLine: View {
    let count: Int
    let noun: String

    var body: some View {
        Text("+ \(count) \(noun)")
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(DTColor.dimmed)
            .padding(.leading, 60)
    }
}

private func projectReviewRows(
    repos: [LocalRepoSnapshot],
    actions: [ActionSnapshot],
    issues: [MatterSnapshot],
    range: ProjectReviewRange
) -> [ProjectReviewRowData] {
    let actionsByProject = Dictionary(
        grouping: actions.filter { range.contains($0.happenedAt) },
        by: \.projectId
    ).mapValues { actions in
        actions.sorted { $0.happenedAt > $1.happenedAt }
    }
    let issuesByProject = Dictionary(
        grouping: issues,
        by: { $0.projectId ?? "" }
    ).mapValues { issues in
        issues.sorted { $0.updatedAt > $1.updatedAt }
    }

    return repos
        .map { repo in
            projectReviewRow(
                repo: repo,
                actions: actionsByProject[repo.project.id] ?? [],
                issues: issuesByProject[repo.project.id] ?? []
            )
        }
        .filter { $0.hasMovement || $0.hasOpenWork }
        .sorted { left, right in
            if left.hasMovement != right.hasMovement {
                return left.hasMovement
            }
            if left.actionCount != right.actionCount {
                return left.actionCount > right.actionCount
            }
            if let leftDate = left.latestAction?.happenedAt, let rightDate = right.latestAction?.happenedAt {
                return leftDate > rightDate
            }
            if left.openWorkCount != right.openWorkCount {
                return left.openWorkCount > right.openWorkCount
            }
            return left.repo.project.title.localizedCaseInsensitiveCompare(right.repo.project.title) == .orderedAscending
        }
}

private func projectReviewRow(
    repo: LocalRepoSnapshot,
    actions: [ActionSnapshot],
    issues: [MatterSnapshot]
) -> ProjectReviewRowData {
    var linkedActionIDs = Set<String>()
    var linkedWork: [ProjectReviewWorkItem] = []

    for issue in issues {
        let linkedActions = actions
            .filter { action in
                actionReferencesIssue(action, issue: issue)
            }
            .sorted { $0.happenedAt > $1.happenedAt }

        if issue.issueKind == "github_pr" || !linkedActions.isEmpty {
            linkedWork.append(ProjectReviewWorkItem(issue: issue, actions: linkedActions))
            linkedActionIDs.formUnion(linkedActions.map(\.id))
        }
    }

    let linkedIssueIDs = Set(linkedWork.map(\.issue.id))
    let unlinkedActions = actions.filter { !linkedActionIDs.contains($0.id) }
    let waitingIssues = issues.filter { !linkedIssueIDs.contains($0.id) }

    return ProjectReviewRowData(
        repo: repo,
        linkedWork: sortReviewWork(linkedWork),
        unlinkedActions: unlinkedActions,
        waitingIssues: waitingIssues
    )
}

private func sortReviewWork(_ workItems: [ProjectReviewWorkItem]) -> [ProjectReviewWorkItem] {
    workItems.sorted { left, right in
        let leftRank = reviewIssueKindRank(left.issue)
        let rightRank = reviewIssueKindRank(right.issue)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        if left.actions.count != right.actions.count {
            return left.actions.count > right.actions.count
        }
        let leftDate = left.actions.first?.happenedAt ?? left.issue.updatedAt
        let rightDate = right.actions.first?.happenedAt ?? right.issue.updatedAt
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return left.issue.text.localizedCaseInsensitiveCompare(right.issue.text) == .orderedAscending
    }
}

private func reviewIssueKindRank(_ issue: MatterSnapshot) -> Int {
    switch issue.issueKind {
    case "github_pr": return 0
    case "github_issue": return 1
    default: return 2
    }
}

private func actionReferencesIssue(_ action: ActionSnapshot, issue: MatterSnapshot) -> Bool {
    guard let summary = action.summary, !summary.isEmpty else {
        return false
    }

    return issueReferenceTokens(issue).contains { token in
        summary.range(of: token, options: [.caseInsensitive]) != nil
    }
}

private func issueReferenceTokens(_ issue: MatterSnapshot) -> [String] {
    var tokens: [String] = []

    if let externalId = issue.externalId?.trimmingCharacters(in: .whitespacesAndNewlines), !externalId.isEmpty {
        if externalId.hasPrefix("#") {
            tokens.append(externalId)
        } else {
            tokens.append("#\(externalId)")
        }
    }

    if let externalUrl = issue.externalUrl,
       let number = externalUrl
        .split(separator: "/")
        .last
        .flatMap({ Int($0) }) {
        tokens.append("#\(number)")
    }

    return Array(Set(tokens))
}

private func formatReviewActionDate(_ isoString: String) -> String {
    guard let date = parseISODate(isoString) else {
        return "--"
    }
    if Calendar.current.isDateInToday(date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}
