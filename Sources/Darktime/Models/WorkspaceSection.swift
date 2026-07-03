import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case capture
    case inbox
    case rootbox
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: return "Capture"
        case .inbox: return "Inbox"
        case .rootbox: return "Rootbox"
        case .calendar: return "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: return "square.and.pencil"
        case .inbox: return "tray.fill"
        case .rootbox: return "tree.fill"
        case .calendar: return "calendar"
        }
    }
}

