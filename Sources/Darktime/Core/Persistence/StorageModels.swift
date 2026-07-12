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
}

struct RootSnapshot: Sendable {
    let id: String
    let title: String
    let intention: String?
    let kind: String
    let localPath: String?
    let createdAt: String
    let updatedAt: String
}

struct LocalRepoSnapshot: Sendable {
    let root: RootSnapshot
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

struct OutputTraceSnapshot: Sendable {
    let id: String
    let rootId: String
    let source: String
    let kind: String
    let externalId: String?
    let happenedAt: String
    let summary: String?
    let metadataJson: String?
    let createdAt: String
}

struct OutputTraceUpsert: Sendable {
    let rootId: String
    let source: String
    let kind: String
    let externalId: String
    let happenedAt: String
    let summary: String?
    let metadataJson: String?
}
