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
    let actionRefs: [ActionRefSnapshot]
    let issues: [MatterSnapshot]
    let range: ProjectReviewRange

    @State private var projection = ProjectReviewProjection.empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if projection.movedRows.isEmpty && projection.waitingRows.isEmpty {
                    EmptyStateLine(
                        systemImage: "clock.arrow.circlepath",
                        title: "No review signal",
                        detail: "Actions and project issues will show up here when there is something to review."
                    )
                } else {
                    ProjectReviewSummaryLine(
                        range: range,
                        movedCount: projection.movedRows.count,
                        waitingCount: projection.waitingRows.count,
                        actionCount: projection.actionCount
                    )

                    if !projection.movedRows.isEmpty {
                        ProjectReviewSectionTitle("Moved Projects")
                        ProjectReviewRowList(model: model, rows: projection.movedRows, rowKind: .moved)
                    }

                    if !projection.waitingRows.isEmpty {
                        ProjectReviewSectionTitle("Waiting Projects")
                        ProjectReviewRowList(model: model, rows: projection.waitingRows, rowKind: .waiting)
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 42)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .onAppear(perform: rebuildProjection)
        .onChange(of: model.reviewRevision) { _ in
            rebuildProjection()
        }
        .onChange(of: range) { _ in
            rebuildProjection()
        }
    }

    private func rebuildProjection() {
        projection = ProjectReviewProjection.make(
            repos: repos,
            actions: actions,
            actionRefs: actionRefs,
            issues: issues,
            range: range
        )
    }
}

private enum ProjectReviewRowKind {
    case moved
    case waiting
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
    @State private var visibleLinkedWorkCount = 3
    @State private var visibleUnlinkedBucketCount = 3
    @State private var visibleWaitingIssueCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !row.linkedWork.isEmpty {
                ProjectReviewGroupLabel("Linked work")
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(visibleLinkedWork) { work in
                        ProjectReviewWorkItemLine(model: model, work: work)
                    }
                    if row.linkedWork.count > visibleLinkedWorkCount {
                        ProjectReviewMoreButton(
                            count: min(10, row.linkedWork.count - visibleLinkedWorkCount)
                        ) {
                            visibleLinkedWorkCount = min(visibleLinkedWorkCount + 10, row.linkedWork.count)
                        }
                    }
                }
            }

            if !row.unlinkedBuckets.isEmpty {
                ProjectReviewGroupLabel("Unlinked actions")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleUnlinkedBuckets) { bucket in
                        ProjectReviewActionBucketLine(bucket: bucket)
                    }
                    if row.unlinkedBuckets.count > visibleUnlinkedBucketCount {
                        ProjectReviewMoreButton(
                            count: min(10, row.unlinkedBuckets.count - visibleUnlinkedBucketCount),
                            isCentered: true
                        ) {
                            visibleUnlinkedBucketCount = min(visibleUnlinkedBucketCount + 10, row.unlinkedBuckets.count)
                        }
                    }
                }
            }

            if !row.waitingIssues.isEmpty {
                ProjectReviewGroupLabel("Waiting issues")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleWaitingIssues, id: \.id) { issue in
                        ProjectReviewIssueLine(model: model, issue: issue)
                    }
                    if row.waitingIssues.count > visibleWaitingIssueCount {
                        ProjectReviewMoreButton(
                            count: min(10, row.waitingIssues.count - visibleWaitingIssueCount)
                        ) {
                            visibleWaitingIssueCount = min(visibleWaitingIssueCount + 10, row.waitingIssues.count)
                        }
                    }
                }
            }
        }
    }

    private var visibleLinkedWork: [ProjectReviewWorkItem] {
        Array(row.linkedWork.prefix(visibleLinkedWorkCount))
    }

    private var visibleUnlinkedBuckets: [ProjectReviewActionBucket] {
        Array(row.unlinkedBuckets.prefix(visibleUnlinkedBucketCount))
    }

    private var visibleWaitingIssues: [MatterSnapshot] {
        Array(row.waitingIssues.prefix(visibleWaitingIssueCount))
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
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DTColor.dimmed)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide details" : "Show details")

                ProjectReviewIssueLine(model: model, issue: work.issue, trailingText: actionCountText)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(orderedActions, id: \.id) { action in
                        ProjectReviewActionLine(action: action, isSubtle: true)
                            .padding(.leading, 20)
                    }
                }
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

    private var orderedActions: [ActionSnapshot] {
        work.actions.sorted { $0.happenedAt > $1.happenedAt }
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

private struct ProjectReviewActionBucketLine: View {
    let bucket: ProjectReviewActionBucket
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DTColor.dimmed)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide details" : "Show details")

                Text(bucket.kindLabel)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
                    .frame(width: 48, alignment: .leading)
                Text(bucket.title)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(actionCountText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(orderedActions, id: \.id) { action in
                        ProjectReviewActionLine(action: action, isSubtle: true)
                            .padding(.leading, 20)
                    }
                }
            }
        }
    }

    private var actionCountText: String {
        let count = bucket.actions.count
        let noun = count == 1 ? "action" : "actions"
        return "\(count) \(noun)"
    }

    private var orderedActions: [ActionSnapshot] {
        bucket.actions.sorted { $0.happenedAt > $1.happenedAt }
    }
}

private struct ProjectReviewMoreButton: View {
    let count: Int
    var isCentered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+ \(count) more")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: isCentered ? .infinity : nil, alignment: isCentered ? .center : .leading)
    }
}
