import Foundation
import SQLite3

extension LocalDatabase {
    private struct ShortcutImportLocation {
        let rootURL: URL

        var inboxURL: URL {
            rootURL.appendingPathComponent("Inbox", isDirectory: true)
        }

        var importedURL: URL {
            rootURL.appendingPathComponent("Imported", isDirectory: true)
        }

        var failedURL: URL {
            rootURL.appendingPathComponent("Failed", isDirectory: true)
        }
    }

    static func shortcutsInboxPath() -> String {
        primaryShortcutImportLocation().inboxURL.path
    }

    static func shortcutsImportedPath() -> String {
        primaryShortcutImportLocation().importedURL.path
    }

    static func shortcutsFailedPath() -> String {
        primaryShortcutImportLocation().failedURL.path
    }

    static func ensureShortcutFolders() throws {
        for location in shortcutImportLocations() {
            try FileManager.default.createDirectory(
                at: location.inboxURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: location.importedURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: location.failedURL,
                withIntermediateDirectories: true
            )
        }
    }

    static func importShortcutInbox() throws -> Int {
        try ensureShortcutFolders()

        var importedCount = 0
        for location in shortcutImportLocations() {
            importedCount += try importShortcutInbox(from: location)
        }

        return importedCount
    }

    static func shortcutPendingFileCount() throws -> Int {
        try ensureShortcutFolders()
        return try shortcutImportLocations().reduce(0) { count, location in
            count + (try shortcutImportFileCount(in: location.inboxURL))
        }
    }

    static func shortcutFailedFileCount() throws -> Int {
        try ensureShortcutFolders()
        return try shortcutImportLocations().reduce(0) { count, location in
            count + (try shortcutImportFileCount(in: location.failedURL))
        }
    }

    static func createShortcutTestCapture(text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StorageError.invalidInput("Shortcut test capture cannot be empty.")
        }

        try ensureShortcutFolders()
        let fileURL = primaryShortcutImportLocation().inboxURL
            .appendingPathComponent("darktime-test-\(UUID().uuidString).txt")
        try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func shortcutPayload(from fileURL: URL) throws -> (text: String, source: String, rawPayloadJson: String?) {
        let data = try Data(contentsOf: fileURL)
        if fileURL.pathExtension.lowercased() == "json" {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw StorageError.invalidInput("Shortcut JSON must be an object.")
            }
            guard let text = dictionary["text"] as? String else {
                throw StorageError.invalidInput("Shortcut JSON is missing text.")
            }
            let source = dictionary["source"] as? String ?? "shortcut"
            return (text, source, String(data: data, encoding: .utf8))
        }

        return (String(decoding: data, as: UTF8.self), "shortcut", nil)
    }

    private static func importShortcutInbox(from location: ShortcutImportLocation) throws -> Int {
        let files = try FileManager.default.contentsOfDirectory(
            at: location.inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "txt" || ext == "json"
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var importedCount = 0
        for fileURL in files {
            do {
                let payload = try shortcutPayload(from: fileURL)
                guard !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw StorageError.invalidInput("Shortcut file is empty.")
                }

                _ = try createMatter(
                    text: payload.text,
                    source: payload.source,
                    rawPayloadJson: payload.rawPayloadJson
                )
                try moveImportedFile(fileURL, to: location.importedURL)
                importedCount += 1
            } catch {
                try? moveImportedFile(fileURL, to: location.failedURL)
            }
        }

        return importedCount
    }

    private static func primaryShortcutImportLocation() -> ShortcutImportLocation {
        ShortcutImportLocation(rootURL: shortcutsAppRootURL())
    }

    private static func shortcutImportLocations() -> [ShortcutImportLocation] {
        [
            ShortcutImportLocation(rootURL: shortcutsAppRootURL()),
            ShortcutImportLocation(rootURL: cloudDocsRootURL())
        ]
    }

    private static func shortcutsAppRootURL() -> URL {
        mobileDocumentsURL()
            .appendingPathComponent("iCloud~is~workflow~my~workflows", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Darktime", isDirectory: true)
    }

    private static func cloudDocsRootURL() -> URL {
        mobileDocumentsURL()
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("Darktime", isDirectory: true)
    }

    private static func mobileDocumentsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
    }

    private static func shortcutImportFileCount(in url: URL) throws -> Int {
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { fileURL in
            let ext = fileURL.pathExtension.lowercased()
            return ext == "txt" || ext == "json"
        }
        .count
    }

    private static func moveImportedFile(_ fileURL: URL, to directoryURL: URL) throws {
        let destination = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(fileURL.lastPathComponent)")
        try FileManager.default.moveItem(at: fileURL, to: destination)
    }
}
