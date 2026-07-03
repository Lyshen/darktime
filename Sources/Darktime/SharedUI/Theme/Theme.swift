import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

enum DTColor {
    static let workspace = Color.white
    static let sidebar = Color(red: 0.93, green: 0.935, blue: 0.94).opacity(0.86)
    static let sidebarSelection = Color.black.opacity(0.065)
    static let header = Color(red: 0.985, green: 0.985, blue: 0.975)
    static let panel = Color.white
    static let row = Color(red: 0.955, green: 0.955, blue: 0.955)
    static let codeBackground = Color(red: 0.94, green: 0.94, blue: 0.94)
    static let line = Color.black.opacity(0.075)
    static let inputBorder = Color.black.opacity(0.2)
    static let text = Color.black.opacity(0.86)
    static let muted = Color.black.opacity(0.58)
    static let dimmed = Color.black.opacity(0.36)
    static let accent = Color.black.opacity(0.82)
    static let green = Color(red: 0.18, green: 0.48, blue: 0.28)
    static let cyan = Color(red: 0.19, green: 0.36, blue: 0.56)
    static let amber = Color(red: 0.68, green: 0.42, blue: 0.12)
    static let red = Color(red: 0.68, green: 0.18, blue: 0.18)
}

func statusColor(_ status: String) -> Color {
    switch status {
    case "success", "ready", "fullAccess", "authorized":
        return DTColor.green
    case "blocked", "started":
        return DTColor.amber
    case "error", "denied", "restricted":
        return DTColor.red
    default:
        return DTColor.cyan
    }
}

func formatRelative(_ isoString: String) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 {
        return "\(max(0, seconds))s ago"
    }
    if seconds < 3600 {
        return "\(seconds / 60)m ago"
    }
    if seconds < 86_400 {
        return "\(seconds / 3600)h ago"
    }

    return formatLocalDateTime(isoString)
}

func formatLocalDateTime(_ isoString: String) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d HH:mm"
    return formatter.string(from: date)
}

func formatLocalTime(_ isoString: String) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

func formatMatterSource(_ source: String) -> String {
    switch source {
    case "quick_capture": return "quick"
    case "manual": return "manual"
    case "shortcut": return "shortcut"
    case "mcp": return "mcp"
    default:
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 12 {
            return trimmed.isEmpty ? "unknown" : trimmed
        }
        return "\(trimmed.prefix(10))..."
    }
}

func parseISODate(_ isoString: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: isoString) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: isoString)
}

extension Color {
    init(hex: String?, fallback: Color) {
        guard
            let hex,
            hex.hasPrefix("#"),
            hex.count == 7,
            let value = Int(hex.dropFirst(), radix: 16)
        else {
            self = fallback
            return
        }

        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}

func fourCharCode(_ value: String) -> OSType {
    var result: OSType = 0
    for scalar in value.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
