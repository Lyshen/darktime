import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct CalendarWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorkspaceTitle(
                    title: "Calendar",
                    detail: "Apple Calendar and local MCP service remain available as a secondary surface.",
                    systemImage: "calendar"
                )
                HStack(alignment: .top, spacing: 16) {
                    SourcesPanel(model: model)
                        .frame(width: 320)
                    VStack(spacing: 16) {
                        StatusPanel(model: model)
                        AgentsPanel(model: model)
                            .frame(minHeight: 220)
                    }
                }
            }
            .padding(20)
        }
    }
}


