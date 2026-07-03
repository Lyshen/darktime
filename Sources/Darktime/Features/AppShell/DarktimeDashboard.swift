import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct DarktimeDashboard: View {
    @ObservedObject var model: DashboardModel
    @AppStorage("darktime.sidebarWidth") private var storedSidebarWidth = 230.0
    @State private var draggingSidebarWidth: Double?
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let minSidebarWidth = 190.0
    private let maxSidebarWidth = 340.0

    var body: some View {
        ZStack {
            DTColor.workspace.ignoresSafeArea()
            HStack(spacing: 0) {
                WorkspaceRail(model: model)
                    .frame(width: CGFloat(sidebarWidth))
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        SidebarResizeHandle(
                            currentWidth: sidebarWidth,
                            minWidth: minSidebarWidth,
                            maxWidth: maxSidebarWidth,
                            onChange: { draggingSidebarWidth = $0 },
                            onEnd: { width in
                                storedSidebarWidth = width
                                draggingSidebarWidth = nil
                            }
                        )
                        .frame(width: 10)
                        .frame(maxHeight: .infinity)
                    }

                workspace
                    .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(DTColor.workspace)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .font(.system(size: 13, weight: .regular, design: .default))
        .foregroundStyle(DTColor.text)
        .onReceive(refreshTimer) { _ in
            model.refresh()
        }
    }

    private var sidebarWidth: Double {
        min(max(draggingSidebarWidth ?? storedSidebarWidth, minSidebarWidth), maxSidebarWidth)
    }

    @ViewBuilder
    private var workspace: some View {
        switch model.selectedSection {
        case .capture:
            CaptureWorkspace(model: model)
        case .inbox:
            InboxWorkspace(model: model)
        case .rootbox:
            RootboxWorkspace(model: model)
        case .calendar:
            CalendarWorkspace(model: model)
        }
    }
}


