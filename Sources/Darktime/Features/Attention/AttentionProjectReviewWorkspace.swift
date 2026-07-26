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
        projection = ProjectReviewProjection(
            rows: projectReviewRows(repos: repos, actions: actions, actionRefs: actionRefs, issues: issues, range: range)
        )
    }
}

private enum ProjectReviewRowKind {
    case moved
    case waiting
}

private struct ProjectReviewProjection {
    let rows: [ProjectReviewRowData]

    static let empty = ProjectReviewProjection(rows: [])

    var movedRows: [ProjectReviewRowData] {
        rows.filter(\.hasMovement)
    }

    var waitingRows: [ProjectReviewRowData] {
        rows.filter { !$0.hasMovement && $0.hasOpenWork }
    }

    var actionCount: Int {
        movedRows.reduce(0) { $0 + $1.actionCount }
    }
}

private struct ProjectReviewRowData: Identifiable {
    let repo: LocalRepoSnapshot
    let linkedWork: [ProjectReviewWorkItem]
    let unlinkedActionGroups: [ProjectReviewActionRefGroup]
    let unlinkedActions: [ActionSnapshot]
    let waitingIssues: [MatterSnapshot]

    var id: String { repo.project.id }

    var latestAction: ActionSnapshot? {
        allActions.first
    }

    var allActions: [ActionSnapshot] {
        (linkedWork.flatMap(\.actions) + unlinkedActionGroups.flatMap(\.actions) + unlinkedActions)
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
    let key: String
    let issue: MatterSnapshot
    let issues: [MatterSnapshot]
    let actions: [ActionSnapshot]

    var id: String { key }
}

private struct ProjectReviewActionRefGroup: Identifiable {
    let key: String
    let displayRef: ActionRefSnapshot
    let actions: [ActionSnapshot]

    var id: String { key }
}

private struct ProjectReviewIssueGroup {
    let key: String
    let displayIssue: MatterSnapshot
    let issues: [MatterSnapshot]
    let referenceTokens: [String]
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
                            count: min(10, row.linkedWork.count - visibleLinkedWorkCount),
                            noun: "more work items"
                        ) {
                            visibleLinkedWorkCount = min(visibleLinkedWorkCount + 10, row.linkedWork.count)
                        }
                    }
                }
            }

            if !unlinkedBuckets.isEmpty {
                ProjectReviewGroupLabel("Unlinked actions")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleUnlinkedBuckets) { bucket in
                        ProjectReviewActionBucketLine(bucket: bucket)
                    }
                    if unlinkedBuckets.count > visibleUnlinkedBucketCount {
                        ProjectReviewMoreButton(
                            count: min(10, unlinkedBuckets.count - visibleUnlinkedBucketCount),
                            noun: "more buckets"
                        ) {
                            visibleUnlinkedBucketCount = min(visibleUnlinkedBucketCount + 10, unlinkedBuckets.count)
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
                            count: min(10, row.waitingIssues.count - visibleWaitingIssueCount),
                            noun: "more issues"
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

    private var unlinkedBuckets: [ProjectReviewActionBucket] {
        let groupedBuckets = row.unlinkedActionGroups.map { group in
            ProjectReviewActionBucket(
                key: group.id,
                kindLabel: bucketKindLabel(for: group.displayRef.refKind),
                title: bucketTitle(for: group.displayRef),
                actions: group.actions,
                sortDate: group.actions.first?.happenedAt ?? group.displayRef.createdAt
            )
        }
        let directBucket: ProjectReviewActionBucket? = row.unlinkedActions.isEmpty ? nil : ProjectReviewActionBucket(
            key: "direct",
            kindLabel: "direct",
            title: "Direct actions",
            actions: row.unlinkedActions,
            sortDate: row.unlinkedActions.first?.happenedAt ?? row.repo.project.updatedAt
        )

        let allBuckets = groupedBuckets + (directBucket.map { [$0] } ?? [])
        return allBuckets
            .sorted { left, right in
                if left.sortDate != right.sortDate {
                    return left.sortDate > right.sortDate
                }
                if left.kindLabel != right.kindLabel {
                    return left.kindLabel < right.kindLabel
                }
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
    }

    private var visibleUnlinkedBuckets: [ProjectReviewActionBucket] {
        Array(unlinkedBuckets.prefix(visibleUnlinkedBucketCount))
    }

    private var visibleWaitingIssues: [MatterSnapshot] {
        Array(row.waitingIssues.prefix(visibleWaitingIssueCount))
    }

    private func bucketKindLabel(for refKind: String) -> String {
        switch refKind {
        case "github_pr":
            return "pr"
        case "github_issue":
            return "gh"
        case "branch":
            return "branch"
        case "direct":
            return "direct"
        default:
            return refKind
        }
    }

    private func bucketTitle(for ref: ActionRefSnapshot) -> String {
        switch ref.refKind {
        case "github_pr", "github_issue":
            if let title = normalized(ref.refTitle), title != ref.refKey {
                return "\(ref.refKey) · \(title)"
            }
            return ref.refKey
        default:
            return normalized(ref.refTitle) ?? ref.refKey
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
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
    let noun: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+ \(count) \(noun)")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
        }
        .buttonStyle(.plain)
        .padding(.leading, 60)
    }
}

private struct ProjectReviewActionBucket: Identifiable {
    let key: String
    let kindLabel: String
    let title: String
    let actions: [ActionSnapshot]
    let sortDate: String

    var id: String { key }
}

private func projectReviewRows(
    repos: [LocalRepoSnapshot],
    actions: [ActionSnapshot],
    actionRefs: [ActionRefSnapshot],
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
    let refsByProject = Dictionary(
        grouping: actionRefs,
        by: \.projectId
    )

    return repos
        .map { repo in
            projectReviewRow(
                repo: repo,
                actions: actionsByProject[repo.project.id] ?? [],
                actionRefs: refsByProject[repo.project.id] ?? [],
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
    actionRefs: [ActionRefSnapshot],
    issues: [MatterSnapshot]
) -> ProjectReviewRowData {
    var linkedActionIDs = Set<String>()
    var linkedWork: [ProjectReviewWorkItem] = []
    let refsByActionID = Dictionary(grouping: actionRefs, by: \.actionId)
    let issueGroups = projectReviewIssueGroups(issues)

    for group in issueGroups {
        let linkedActions = actions
            .filter { action in
                actionReferencesIssueGroup(
                    action,
                    refs: refsByActionID[action.id] ?? [],
                    issueGroup: group
                )
            }
            .sorted { $0.happenedAt > $1.happenedAt }

        if group.displayIssue.issueKind == "github_pr" || !linkedActions.isEmpty {
            linkedWork.append(ProjectReviewWorkItem(
                key: group.key,
                issue: group.displayIssue,
                issues: group.issues,
                actions: linkedActions
            ))
            linkedActionIDs.formUnion(linkedActions.map(\.id))
        }
    }

    let linkedIssueIDs = Set(linkedWork.map(\.key))
    let unlinkedCandidates = actions.filter { !linkedActionIDs.contains($0.id) }
    let unlinkedActionGroups = groupUnlinkedActions(unlinkedCandidates, refsByActionID: refsByActionID)
    let groupedActionIDs = Set(unlinkedActionGroups.flatMap(\.actions).map(\.id))
    let unlinkedActions = unlinkedCandidates.filter { !groupedActionIDs.contains($0.id) }
    let waitingIssues = issueGroups
        .filter { !linkedIssueIDs.contains($0.key) }
        .map(\.displayIssue)

    return ProjectReviewRowData(
        repo: repo,
        linkedWork: sortReviewWork(linkedWork),
        unlinkedActionGroups: unlinkedActionGroups,
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

private func projectReviewIssueGroups(_ issues: [MatterSnapshot]) -> [ProjectReviewIssueGroup] {
    let grouped = Dictionary(grouping: issues, by: reviewIssueGroupKey)

    return grouped.compactMap { key, groupIssues in
        guard let displayIssue = preferredDisplayIssue(in: groupIssues) else {
            return nil
        }

        let tokens = Array(Set(groupIssues.flatMap(issueReferenceTokens)))
        return ProjectReviewIssueGroup(
            key: key,
            displayIssue: displayIssue,
            issues: groupIssues.sorted { $0.updatedAt > $1.updatedAt },
            referenceTokens: tokens
        )
    }
    .sorted { left, right in
        let leftDate = left.displayIssue.updatedAt
        let rightDate = right.displayIssue.updatedAt
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        let leftRank = reviewIssueKindRank(left.displayIssue)
        let rightRank = reviewIssueKindRank(right.displayIssue)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return left.displayIssue.text.localizedCaseInsensitiveCompare(right.displayIssue.text) == .orderedAscending
    }
}

private func reviewIssueGroupKey(_ issue: MatterSnapshot) -> String {
    if let token = githubReferenceToken(issue.externalId, externalUrl: issue.externalUrl) {
        return canonicalReviewRefKey(kind: issue.issueKind ?? "manual", key: token)
    }
    return "matter:\(issue.id)"
}

private func githubReferenceToken(_ externalId: String?, externalUrl: String?) -> String? {
    if let externalId = externalId?.trimmingCharacters(in: .whitespacesAndNewlines), !externalId.isEmpty {
        return normalizedGitHubReference(externalId)
    }

    if let externalUrl,
       let number = externalUrl
           .split(separator: "/")
           .last
           .flatMap({ Int($0) }) {
        return "#\(number)"
    }

    return nil
}

private func normalizedGitHubReference(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("#") {
        return trimmed.lowercased()
    }
    return "#\(trimmed)".lowercased()
}

private func canonicalReviewRefKey(kind: String, key: String) -> String {
    let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

    switch normalizedKind {
    case "github_pr", "github_issue":
        return "github:\(normalizedGitHubReference(normalizedKey))"
    default:
        return "\(normalizedKind):\(normalizedKey.lowercased())"
    }
}

private func preferredDisplayIssue(in issues: [MatterSnapshot]) -> MatterSnapshot? {
    issues.sorted { left, right in
        let leftRank = reviewIssueDisplayRank(left)
        let rightRank = reviewIssueDisplayRank(right)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        if left.updatedAt != right.updatedAt {
            return left.updatedAt > right.updatedAt
        }
        return left.text.localizedCaseInsensitiveCompare(right.text) == .orderedAscending
    }
    .first
}

private func reviewIssueDisplayRank(_ issue: MatterSnapshot) -> Int {
    switch issue.issueKind {
    case "github_pr": return 0
    case "github_issue": return 1
    default: return 2
    }
}

private func reviewIssueKindRank(_ issue: MatterSnapshot) -> Int {
    switch issue.issueKind {
    case "github_pr": return 0
    case "github_issue": return 1
    default: return 2
    }
}

private func actionReferencesIssueGroup(
    _ action: ActionSnapshot,
    refs: [ActionRefSnapshot],
    issueGroup: ProjectReviewIssueGroup
) -> Bool {
    if refs.contains(where: { canonicalReviewRefKey(kind: $0.refKind, key: $0.refKey) == issueGroup.key }) {
        return true
    }

    guard let summary = action.summary, !summary.isEmpty else {
        return false
    }

    return issueGroup.referenceTokens.contains { token in
        summary.range(of: token, options: [.caseInsensitive]) != nil
    }
}

private func groupUnlinkedActions(
    _ actions: [ActionSnapshot],
    refsByActionID: [String: [ActionRefSnapshot]]
) -> [ProjectReviewActionRefGroup] {
    var actionsByGroupID: [String: [ActionSnapshot]] = [:]
    var refsByGroupID: [String: [ActionRefSnapshot]] = [:]

    for action in actions {
        guard let ref = preferredReviewRef(refsByActionID[action.id] ?? []) else {
            continue
        }
        let groupID = canonicalReviewRefKey(kind: ref.refKind, key: ref.refKey)
        refsByGroupID[groupID, default: []].append(ref)
        actionsByGroupID[groupID, default: []].append(action)
    }

    return actionsByGroupID.compactMap { groupID, actions in
        guard let refs = refsByGroupID[groupID], let displayRef = preferredReviewRef(refs) else {
            return nil
        }
        return ProjectReviewActionRefGroup(
            key: groupID,
            displayRef: displayRef,
            actions: actions.sorted { $0.happenedAt > $1.happenedAt }
        )
    }
    .sorted { left, right in
        let leftDate = left.actions.first?.happenedAt ?? left.displayRef.createdAt
        let rightDate = right.actions.first?.happenedAt ?? right.displayRef.createdAt
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        let leftRank = reviewRefKindRank(left.displayRef.refKind)
        let rightRank = reviewRefKindRank(right.displayRef.refKind)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return left.displayRef.refKey.localizedCaseInsensitiveCompare(right.displayRef.refKey) == .orderedAscending
    }
}

private func preferredReviewRef(_ refs: [ActionRefSnapshot]) -> ActionRefSnapshot? {
    refs.sorted { left, right in
        let leftRank = reviewRefKindRank(left.refKind)
        let rightRank = reviewRefKindRank(right.refKind)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return left.refKey.localizedCaseInsensitiveCompare(right.refKey) == .orderedAscending
    }
    .first
}

private func reviewRefKindRank(_ kind: String) -> Int {
    switch kind {
    case "github_pr": return 0
    case "github_issue": return 1
    case "branch": return 2
    default: return 3
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
