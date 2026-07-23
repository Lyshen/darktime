import Foundation
import SQLite3

enum LocalDatabase {
    static let matterStatuses = ["inbox", "issue", "done", "dropped"]
}

enum StorageError: LocalizedError {
    case sqlite(String)
    case invalidInput(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message), .invalidInput(let message), .notFound(let message):
            return message
        }
    }
}

let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
