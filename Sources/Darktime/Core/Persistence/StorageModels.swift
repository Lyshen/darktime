import Foundation

struct MCPSessionSnapshot: Sendable {
    let id: String
    let clientName: String
    let clientVersion: String?
    let transport: String
    let startedAt: String
    let lastSeenAt: String
    let lastToolName: String?
    let lastToolStatus: String?
    let toolCallCount: Int
}

struct ActionLogSnapshot: Sendable {
    let id: Int64
    let createdAt: String
    let sessionId: String?
    let clientName: String?
    let source: String
    let action: String
    let status: String
    let isWrite: Bool
    let summary: String?
    let errorCode: String?
    let errorMessage: String?
    let requestJson: String?
    let responseJson: String?
}

struct MatterSnapshot: Sendable {
    let id: String
    let text: String
    let status: String
    let source: String
    let createdAt: String
    let updatedAt: String
    let rawPayloadJson: String?
    let projectId: String?
    let issueKind: String?
    let externalId: String?
    let externalUrl: String?
    let externalState: String?
}

struct ProjectSnapshot: Sendable {
    let id: String
    let title: String
    let intention: String?
    let kind: String
    let localPath: String?
    let createdAt: String
    let updatedAt: String
}

struct LocalRepoSnapshot: Sendable {
    let project: ProjectSnapshot
    let repoName: String
    let rootPath: String
    let branch: String
    let lastCommitAt: String?
    let latestCommitSummary: String?
    let commitsLast2Days: Int
    let commitsLast7Days: Int
    let commitsLast30Days: Int
    let hasUncommittedChanges: Bool
    let state: String
    let openIssueCount: Int
}

struct MatterLogSnapshot: Sendable {
    let id: Int64
    let matterId: String
    let createdAt: String
    let action: String
    let fromStatus: String?
    let toStatus: String?
    let summary: String?
    let metadataJson: String?
}

struct ActionSnapshot: Sendable {
    let id: String
    let projectId: String
    let source: String
    let kind: String
    let externalId: String?
    let happenedAt: String
    let summary: String?
    let metadataJson: String?
    let createdAt: String
}

struct ActionRefSnapshot: Sendable, Hashable {
    let actionId: String
    let projectId: String
    let refKind: String
    let refKey: String
    let refTitle: String?
    let refUrl: String?
    let createdAt: String
}

struct ActionUpsert: Sendable {
    let projectId: String
    let source: String
    let kind: String
    let externalId: String
    let happenedAt: String
    let summary: String?
    let metadataJson: String?
    let refs: [ActionRefUpsert]

    init(
        projectId: String,
        source: String,
        kind: String,
        externalId: String,
        happenedAt: String,
        summary: String?,
        metadataJson: String?,
        refs: [ActionRefUpsert] = []
    ) {
        self.projectId = projectId
        self.source = source
        self.kind = kind
        self.externalId = externalId
        self.happenedAt = happenedAt
        self.summary = summary
        self.metadataJson = metadataJson
        self.refs = refs
    }
}

struct ActionRefUpsert: Sendable, Hashable {
    let kind: String
    let key: String
    let title: String?
    let url: String?
}
