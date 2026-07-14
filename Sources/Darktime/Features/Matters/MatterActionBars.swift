import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct InboxClearActionBar: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot

    var body: some View {
        HStack(spacing: 8) {
            action("Drop", "xmark", "dropped", tint: DTColor.dimmed)
            action("Later", "clock", "later", tint: DTColor.cyan)
            action("Done", "checkmark", "done", tint: DTColor.green)
            action("Issue", "circle.dotted", "issue", tint: DTColor.green)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func action(_ title: String, _ image: String, _ status: String, tint: Color) -> some View {
        Button {
            model.moveMatter(matter, to: status)
        } label: {
            Label(title, systemImage: image)
        }
        .disabled(matter.status == status)
        .tint(tint)
    }
}

struct IssueActionBar: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.moveMatter(matter, to: "inbox")
            } label: {
                Label("Move to Inbox", systemImage: "tray")
            }
            .tint(DTColor.cyan)

            Button {
                model.moveMatter(matter, to: "dropped")
            } label: {
                Label("Drop", systemImage: "xmark")
            }
            .tint(DTColor.dimmed)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

