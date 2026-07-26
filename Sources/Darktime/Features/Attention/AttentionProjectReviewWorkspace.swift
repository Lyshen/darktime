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

    private var activeRows: [ProjectReviewRowData] {
        rows.filter { !$0.actions.isEmpty }
    }

    private var quietRows: [ProjectReviewRowData] {
        rows.filter { $0.actions.isEmpty && !$0.issues.isEmpty }
    }

    private var actionCount: Int {
        activeRows.reduce(0) { $0 + $1.actions.count }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if activeRows.isEmpty && quietRows.isEmpty {
                    EmptyStateLine(
                        systemImage: "clock.arrow.circlepath",
                        title: "No review signal",
                        detail: "Actions and project issues will show up here when there is something to review."
                    )
                } else {
                    ProjectReviewSummaryLine(
                        range: range,
                        activeCount: activeRows.count,
                        quietCount: quietRows.count,
                        actionCount: actionCount
                    )

                    if !activeRows.isEmpty {
                        ProjectReviewSectionTitle("Active Projects")
                        ProjectReviewRowList(model: model, rows: activeRows, rowKind: .active)
                    }

                    if !quietRows.isEmpty {
                        ProjectReviewSectionTitle("Quiet With Issues")
                        ProjectReviewRowList(model: model, rows: quietRows, rowKind: .quiet)
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
    case active
    case quiet
}

private struct ProjectReviewRowData: Identifiable {
    let repo: LocalRepoSnapshot
    let actions: [ActionSnapshot]
    let issues: [MatterSnapshot]

    var id: String { repo.project.id }

    var latestAction: ActionSnapshot? {
        actions.first
    }
}

private struct ProjectReviewSummaryLine: View {
    let range: ProjectReviewRange
    let activeCount: Int
    let quietCount: Int
    let actionCount: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(range.title)
                .foregroundStyle(DTColor.text)
            Text("·")
                .foregroundStyle(DTColor.dimmed)
            Text("\(activeCount) active")
            Text("·")
                .foregroundStyle(DTColor.dimmed)
            Text("\(quietCount) quiet")
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
            Image(systemName: rowKind == .active ? "waveform.path.ecg" : "pause.circle")
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

                ProjectReviewActionLines(actions: Array(row.actions.prefix(3)))
                ProjectReviewIssueLines(model: model, issues: Array(row.issues.prefix(3)))
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
        rowKind == .active ? DTColor.green : DTColor.amber
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
        let count = row.actions.count
        guard count > 0 else {
            return "no action"
        }
        let noun = count == 1 ? "action" : "actions"
        return "\(count) \(noun)"
    }

    private var issueText: String {
        let count = row.issues.count
        let noun = count == 1 ? "issue" : "issues"
        return "\(count) \(noun)"
    }

    private var stateText: String {
        row.actions.isEmpty ? "quiet" : "active"
    }
}

private struct ProjectReviewActionLines: View {
    let actions: [ActionSnapshot]

    var body: some View {
        if actions.isEmpty {
            Text("No actions in this range")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(actions, id: \.id) { action in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatReviewActionDate(action.happenedAt))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(DTColor.dimmed)
                            .frame(width: 54, alignment: .leading)
                        Text(action.summary ?? "Action")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.muted)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct ProjectReviewIssueLines: View {
    @ObservedObject var model: DashboardModel
    let issues: [MatterSnapshot]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues, id: \.id) { issue in
                    if issue.externalUrl != nil {
                        Button {
                            model.openExternalIssue(issue)
                        } label: {
                            ProjectReviewIssueLine(issue: issue)
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProjectReviewIssueLine(issue: issue)
                    }
                }
            }
        }
    }
}

private struct ProjectReviewIssueLine: View {
    let issue: MatterSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(issueKind)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 54, alignment: .leading)
            Text(issue.text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text.opacity(0.72))
                .lineLimit(1)
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
            ProjectReviewRowData(
                repo: repo,
                actions: actionsByProject[repo.project.id] ?? [],
                issues: issuesByProject[repo.project.id] ?? []
            )
        }
        .filter { !$0.actions.isEmpty || !$0.issues.isEmpty }
        .sorted { left, right in
            if left.actions.isEmpty != right.actions.isEmpty {
                return !left.actions.isEmpty
            }
            if left.actions.count != right.actions.count {
                return left.actions.count > right.actions.count
            }
            if let leftDate = left.latestAction?.happenedAt, let rightDate = right.latestAction?.happenedAt {
                return leftDate > rightDate
            }
            if left.issues.count != right.issues.count {
                return left.issues.count > right.issues.count
            }
            return left.repo.project.title.localizedCaseInsensitiveCompare(right.repo.project.title) == .orderedAscending
        }
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
