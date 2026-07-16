import Foundation

struct LocalGitCommitAction: Sendable {
    let hash: String
    let date: String
    let summary: String
}

struct LocalGitPullRequestIssue: Sendable {
    let number: Int
    let title: String
    let url: String
    let state: String
    let updatedAt: String?

    var externalId: String {
        "#\(number)"
    }
}

enum LocalGitRepositoryService {
    static func resolveRepository(at path: String) throws -> (title: String, rootPath: String) {
        let rootPath = try runGit(
            arguments: ["-C", path, "rev-parse", "--show-toplevel"],
            allowFailure: false
        )
        let trimmedRoot = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoot.isEmpty else {
            throw LocalGitRepositoryError.notRepository
        }

        return (
            title: URL(fileURLWithPath: trimmedRoot, isDirectory: true).lastPathComponent,
            rootPath: trimmedRoot
        )
    }

    static func inspect(project: ProjectSnapshot) -> LocalRepoSnapshot? {
        guard let localPath = project.localPath else {
            return nil
        }

        do {
            let resolved = try resolveRepository(at: localPath)
            let branch = currentBranch(at: resolved.rootPath)
            let latestCommit = latestCommit(at: resolved.rootPath)
            let hasUncommittedChanges = hasUncommittedChanges(at: resolved.rootPath)

            return LocalRepoSnapshot(
                project: project,
                repoName: resolved.title,
                rootPath: resolved.rootPath,
                branch: branch,
                lastCommitAt: latestCommit?.date,
                latestCommitSummary: latestCommit?.summary,
                commitsLast2Days: commitCount(at: resolved.rootPath, since: "2 days ago"),
                commitsLast7Days: commitCount(at: resolved.rootPath, since: "7 days ago"),
                commitsLast30Days: commitCount(at: resolved.rootPath, since: "30 days ago"),
                hasUncommittedChanges: hasUncommittedChanges,
                state: state(lastCommitAt: latestCommit?.date),
                openIssueCount: 0
            )
        } catch {
            return LocalRepoSnapshot(
                project: project,
                repoName: project.title,
                rootPath: localPath,
                branch: "unavailable",
                lastCommitAt: nil,
                latestCommitSummary: "Unable to read this repository",
                commitsLast2Days: 0,
                commitsLast7Days: 0,
                commitsLast30Days: 0,
                hasUncommittedChanges: false,
                state: "unavailable",
                openIssueCount: 0
            )
        }
    }

    static func commitActions(at path: String, since: String = "1 year ago") throws -> [LocalGitCommitAction] {
        let recent = try gitCommitActions(
            arguments: ["-C", path, "log", "--since=\(since)", "--max-count=800", "--format=%H%x1f%cI%x1f%s"]
        )

        if !recent.isEmpty {
            return recent
        }

        return try gitCommitActions(
            arguments: ["-C", path, "log", "-1", "--format=%H%x1f%cI%x1f%s"]
        )
    }

    static func githubRepositorySlug(at path: String) -> String? {
        guard
            let remote = try? runGit(
                arguments: ["-C", path, "remote", "get-url", "origin"],
                allowFailure: true
            )
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !remote.isEmpty
        else {
            return nil
        }
        return parseGitHubSlug(remote)
    }

    static func openPullRequestIssues(repoSlug: String) throws -> [LocalGitPullRequestIssue] {
        let output = try runTool(
            executable: "/usr/bin/env",
            arguments: [
                "gh",
                "pr",
                "list",
                "--repo",
                repoSlug,
                "--state",
                "open",
                "--limit",
                "100",
                "--json",
                "number,title,url,state,updatedAt"
            ],
            allowFailure: false,
            timeout: 12
        )

        struct GHPullRequest: Decodable {
            let number: Int
            let title: String
            let url: String
            let state: String
            let updatedAt: String?
        }

        return try JSONDecoder().decode([GHPullRequest].self, from: Data(output.utf8))
            .map {
                LocalGitPullRequestIssue(
                    number: $0.number,
                    title: $0.title,
                    url: $0.url,
                    state: $0.state.lowercased(),
                    updatedAt: $0.updatedAt
                )
            }
    }

    private static func currentBranch(at path: String) -> String {
        let branch = (try? runGit(
            arguments: ["-C", path, "branch", "--show-current"],
            allowFailure: true
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !branch.isEmpty {
            return branch
        }

        return (try? runGit(
            arguments: ["-C", path, "rev-parse", "--short", "HEAD"],
            allowFailure: true
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    private static func latestCommit(at path: String) -> (date: String, summary: String)? {
        guard let output = try? runGit(
            arguments: ["-C", path, "log", "-1", "--format=%cI%x1f%s"],
            allowFailure: true
        ) else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
        guard let date = parts.first else {
            return nil
        }

        return (
            date: String(date),
            summary: parts.count > 1 ? String(parts[1]) : "Commit"
        )
    }

    private static func gitCommitActions(arguments: [String]) throws -> [LocalGitCommitAction] {
        let output = try runGit(arguments: arguments, allowFailure: false)

        return output
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2 else {
                    return nil
                }

                return LocalGitCommitAction(
                    hash: String(parts[0]),
                    date: String(parts[1]),
                    summary: parts.count > 2 ? String(parts[2]) : "Commit"
                )
            }
    }

    private static func commitCount(at path: String, since: String) -> Int {
        let output = try? runGit(
            arguments: ["-C", path, "rev-list", "--count", "--since=\(since)", "HEAD"],
            allowFailure: true
        )
        return Int(output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    private static func hasUncommittedChanges(at path: String) -> Bool {
        let output = try? runGit(
            arguments: ["-C", path, "status", "--porcelain"],
            allowFailure: true
        )
        return !(output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func state(lastCommitAt: String?) -> String {
        guard
            let lastCommitAt,
            let date = parseGitDate(lastCommitAt)
        else {
            return "empty"
        }

        let days = Date().timeIntervalSince(date) / 86_400
        if days <= 2 {
            return "alive"
        }
        if days <= 7 {
            return "quiet"
        }
        if days <= 30 {
            return "fading"
        }
        return "inactive"
    }

    private static func parseGitDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func parseGitHubSlug(_ remote: String) -> String? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"^git@github\.com:([^/]+)/(.+?)(?:\.git)?$"#,
            #"^https://github\.com/([^/]+)/(.+?)(?:\.git)?$"#,
            #"^ssh://git@github\.com/([^/]+)/(.+?)(?:\.git)?$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range), match.numberOfRanges >= 3 else {
                continue
            }
            guard
                let ownerRange = Range(match.range(at: 1), in: trimmed),
                let repoRange = Range(match.range(at: 2), in: trimmed)
            else {
                continue
            }

            let owner = String(trimmed[ownerRange])
            let repo = String(trimmed[repoRange]).replacingOccurrences(of: ".git", with: "")
            return "\(owner)/\(repo)"
        }

        return nil
    }

    private static func runGit(arguments: [String], allowFailure: Bool, timeout: TimeInterval = 8) throws -> String {
        try runTool(
            executable: "/usr/bin/git",
            arguments: arguments,
            allowFailure: allowFailure,
            timeout: timeout
        )
    }

    private static func runTool(
        executable: String,
        arguments: [String],
        allowFailure: Bool,
        timeout: TimeInterval
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = toolEnvironment()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw LocalGitRepositoryError.commandFailed("Command timed out.")
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0, !allowFailure {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LocalGitRepositoryError.commandFailed(message ?? "Unable to run command.")
        }

        return text
    }

    private static func toolEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let currentPath = environment["PATH"], !currentPath.isEmpty {
            environment["PATH"] = "\(defaultPath):\(currentPath)"
        } else {
            environment["PATH"] = defaultPath
        }
        return environment
    }
}

enum LocalGitRepositoryError: LocalizedError {
    case notRepository
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRepository:
            return "Choose a folder inside a git repository."
        case .commandFailed(let message):
            return message
        }
    }
}
