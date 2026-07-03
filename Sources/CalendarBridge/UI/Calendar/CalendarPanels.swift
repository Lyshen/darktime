import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct SourcesPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Sources", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 14) {
                SourceConnectionRow(
                    name: "Apple Calendar",
                    detail: appleDetail,
                    status: model.canReadWrite ? "connected" : model.authorizationStatus,
                    statusColor: model.canReadWrite ? DTColor.green : DTColor.amber,
                    systemImage: "apple.logo"
                )

                if let preferred = model.preferredCalendar {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow("Write Target")
                        CalendarMiniRow(calendar: preferred, isPreferred: true)
                    }
                } else {
                    EmptyStateLine(
                        systemImage: "calendar.badge.exclamationmark",
                        title: "No writable target",
                        detail: "Grant Calendar access to enable Apple Calendar writes."
                    )
                }

                Divider().overlay(DTColor.line)

                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow("Apple Calendars")
                    if model.calendars.isEmpty {
                        Text("No calendars visible yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(DTColor.muted)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.calendars, id: \.calendarId) { calendar in
                                    CalendarMiniRow(calendar: calendar, isPreferred: calendar.calendarId == model.preferredCalendar?.calendarId)
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }

                Divider().overlay(DTColor.line)

                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow("Planned")
                    PlannedSourceRow(name: "Google Calendar")
                    PlannedSourceRow(name: "Feishu Calendar")
                    PlannedSourceRow(name: "Outlook")
                    PlannedSourceRow(name: "WeCom")
                }
            }
        }
    }

    private var appleDetail: String {
        if model.canReadWrite {
            return "\(model.calendars.count) visible, \(model.writableCalendars.count) writable"
        }
        return "Grant macOS permission before agents can read or write."
    }
}

struct StatusPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Local Service", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    MetricTile(title: "MCP", value: "stdio", detail: "client-launched", tint: DTColor.cyan, systemImage: "terminal")
                    MetricTile(
                        title: "Store",
                        value: model.storageReady ? "ready" : "error",
                        detail: model.storageReady ? "SQLite" : "check logs",
                        tint: model.storageReady ? DTColor.green : DTColor.red,
                        systemImage: "cylinder.split.1x2"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow("MCP Command")
                    HStack(spacing: 10) {
                        Text(model.mcpCommand())
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(DTColor.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DTColor.codeBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button {
                            model.copyMCPCommand()
                        } label: {
                            Label(model.copiedCommand ? "Copied" : "Copy", systemImage: model.copiedCommand ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                InfoGrid(rows: [
                    ("Calendar permission", model.authorizationStatus),
                    ("Database", model.dbPath),
                    ("Service health", model.storageReady ? "ready" : (model.storageError ?? "unavailable"))
                ])
            }
        }
    }
}

struct AgentsPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Agent Access", systemImage: "person.crop.circle.badge.checkmark") {
            if model.sessions.isEmpty {
                EmptyStateLine(
                    systemImage: "terminal",
                    title: "No MCP sessions yet",
                    detail: "Start Codex, Claude Code, or another MCP client with the command above."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.sessions, id: \.id) { session in
                            AgentRow(session: session)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}


