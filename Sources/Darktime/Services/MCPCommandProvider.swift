import Foundation

enum MCPCommandProvider {
    static func command(bundle: Bundle = .main) -> String {
        let appURL = bundle.bundleURL
        let distRepoRoot = appURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildRepoRoot = appURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            distRepoRoot.appendingPathComponent("dist").appendingPathComponent("mcp-server.js"),
            buildRepoRoot.appendingPathComponent("dist").appendingPathComponent("mcp-server.js")
        ]

        if let mcpServer = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return "node \(shellQuote(mcpServer.path))"
        }

        return "node /path/to/darktime/dist/mcp-server.js"
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

