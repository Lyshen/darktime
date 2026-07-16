import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case capture
    case today
    case inbox
    case attention
    case dropped
    case shortcutCapture
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: return "Capture"
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .attention: return "Attention"
        case .dropped: return "Dropped"
        case .shortcutCapture: return "Shortcut Capture"
        case .calendar: return "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: return "square.and.pencil"
        case .today: return "sun.max"
        case .inbox: return "tray.fill"
        case .attention: return "scope"
        case .dropped: return "xmark.circle"
        case .shortcutCapture: return "iphone"
        case .calendar: return "calendar"
        }
    }
}
