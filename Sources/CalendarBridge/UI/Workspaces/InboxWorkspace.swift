import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct InboxWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        MatterWorkspace(
            systemImage: "tray.fill",
            title: "Inbox",
            detail: "Captured matters, waiting to be cleared.",
            matters: model.inboxMatters,
            emptyTitle: "Inbox is clear",
            emptyDetail: "Use quick capture to unload the next open loop.",
            model: model
        )
    }
}


