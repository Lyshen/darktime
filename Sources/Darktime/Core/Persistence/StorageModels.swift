import Foundation

struct MCPSessionSnapshot {
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

struct ActionLogSnapshot {
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

struct MatterSnapshot {
    let id: String
    let text: String
    let status: String
    let source: String
    let createdAt: String
    let updatedAt: String
    let rawPayloadJson: String?
}

struct RootSnapshot {
    let id: String
    let title: String
    let intention: String?
    let kind: String
    let localPath: String?
    let createdAt: String
    let updatedAt: String
}

struct LocalRepoSnapshot {
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

struct MatterLogSnapshot {
    let id: Int64
    let matterId: String
    let createdAt: String
    let action: String
    let fromStatus: String?
    let toStatus: String?
    let summary: String?
    let metadataJson: String?
}
