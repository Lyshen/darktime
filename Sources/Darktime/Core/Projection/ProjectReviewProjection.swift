import Foundation

struct ProjectReviewProjection {
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

    static func make(
        repos: [LocalRepoSnapshot],
        actions: [ActionSnapshot],
        actionRefs: [ActionRefSnapshot],
        issues: [MatterSnapshot],
        range: ProjectReviewRange
    ) -> ProjectReviewProjection {
        ProjectReviewProjection(
            rows: projectReviewRows(
                repos: repos,
                actions: actions,
                actionRefs: actionRefs,
                issues: issues,
                range: range
            )
        )
    }
}

struct ProjectReviewRowData: Identifiable {
    let repo: LocalRepoSnapshot
    let linkedWork: [ProjectReviewWorkItem]
    let unlinkedBuckets: [ProjectReviewActionBucket]
    let waitingIssues: [MatterSnapshot]

    var id: String { repo.project.id }

    var latestAction: ActionSnapshot? {
        allActions.first
    }

    var allActions: [ActionSnapshot] {
        (linkedWork.flatMap(\.actions) + unlinkedBuckets.flatMap(\.actions))
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

struct ProjectReviewWorkItem: Identifiable {
    let key: String
    let issue: MatterSnapshot
    let issues: [MatterSnapshot]
    let actions: [ActionSnapshot]

    var id: String { key }
}

struct ProjectReviewActionBucket: Identifiable {
    let key: String
    let kindLabel: String
    let title: String
    let actions: [ActionSnapshot]
    let sortDate: String

    var id: String { key }
}

private struct ProjectReviewIssueGroup {
    let key: String
    let displayIssue: MatterSnapshot
    let issues: [MatterSnapshot]
    let referenceTokens: [String]
}

func projectReviewRows(
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
    let unlinkedBuckets = projectReviewActionBuckets(
        actions: unlinkedCandidates,
        refsByActionID: refsByActionID,
        fallbackTitle: repo.project.title
    )
    let waitingIssues = issueGroups
        .filter { !linkedIssueIDs.contains($0.key) }
        .map(\.displayIssue)

    return ProjectReviewRowData(
        repo: repo,
        linkedWork: sortReviewWork(linkedWork),
        unlinkedBuckets: unlinkedBuckets,
        waitingIssues: waitingIssues
    )
}

private func projectReviewActionBuckets(
    actions: [ActionSnapshot],
    refsByActionID: [String: [ActionRefSnapshot]],
    fallbackTitle: String
) -> [ProjectReviewActionBucket] {
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

    if !actions.isEmpty {
        let directGroupID = "direct:\(fallbackTitle.lowercased())"
        actionsByGroupID[directGroupID, default: []].append(contentsOf: actions.filter { action in
            preferredReviewRef(refsByActionID[action.id] ?? []) == nil
        })
    }

    let groupedBuckets = actionsByGroupID.compactMap { groupID, groupedActions -> ProjectReviewActionBucket? in
        if let refs = refsByGroupID[groupID], let displayRef = preferredReviewRef(refs) {
            return ProjectReviewActionBucket(
                key: groupID,
                kindLabel: bucketKindLabel(for: displayRef.refKind),
                title: bucketTitle(for: displayRef),
                actions: groupedActions.sorted { $0.happenedAt > $1.happenedAt },
                sortDate: groupedActions.first?.happenedAt ?? displayRef.createdAt
            )
        }

        guard groupID.hasPrefix("direct:") else {
            return nil
        }

        return ProjectReviewActionBucket(
            key: groupID,
            kindLabel: "direct",
            title: "Direct actions",
            actions: groupedActions.sorted { $0.happenedAt > $1.happenedAt },
            sortDate: groupedActions.first?.happenedAt ?? isoNow()
        )
    }

    return groupedBuckets.sorted { left, right in
        if left.sortDate != right.sortDate {
            return left.sortDate > right.sortDate
        }
        if left.kindLabel != right.kindLabel {
            return left.kindLabel < right.kindLabel
        }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}

private func isoNow() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
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
