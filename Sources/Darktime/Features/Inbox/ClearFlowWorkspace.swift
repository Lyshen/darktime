import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

private struct ClearSessionSummary {
    var startedCount = 0
    var droppedCount = 0
    var doneCount = 0
    var keptCount = 0

    var totalResolved: Int {
        droppedCount + doneCount + keptCount
    }

    var remainingCount: Int {
        max(0, startedCount - totalResolved)
    }

    var actionRows: [(title: String, count: Int, tint: Color)] {
        [
            ("Dropped", droppedCount, DTColor.dimmed),
            ("Done", doneCount, DTColor.green),
            ("Kept", keptCount, DTColor.green)
        ].filter { $0.count > 0 }
    }

    mutating func record(_ status: String) {
        if startedCount == 0 {
            startedCount = 1
        }

        switch status {
        case "dropped":
            droppedCount += 1
        case "done":
            doneCount += 1
        case "rootbox":
            keptCount += 1
        default:
            break
        }
    }
}

struct ClearFlowWorkspace: View {
    @ObservedObject var model: DashboardModel
    let onExit: () -> Void
    @State private var currentIndex = 0
    @State private var session = ClearSessionSummary()
    @State private var isShowingSummary = false

    private var currentMatter: MatterSnapshot? {
        let matters = model.inboxMatters
        guard !matters.isEmpty else {
            return nil
        }
        return matters[min(currentIndex, matters.count - 1)]
    }

    private var shouldShowSummary: Bool {
        isShowingSummary || currentMatter == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ClearHeader(
                detail: headerDetail,
                actionTitle: shouldShowSummary ? "Inbox" : "Finish",
                onAction: finishSession
            )
            Divider().overlay(DTColor.line.opacity(0.7))

            ZStack {
                if shouldShowSummary {
                    ClearSessionSummaryView(
                        summary: session,
                        isComplete: currentMatter == nil,
                        onReturn: onExit
                    )
                } else if let matter = currentMatter {
                    ClearMatterFocus(
                        matter: matter,
                        onDrop: { resolve(matter, as: "dropped") },
                        onDone: { resolve(matter, as: "done") },
                        onKeep: { resolve(matter, as: "rootbox") }
                    )
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 36)
                } else {
                    ClearSessionSummaryView(
                        summary: session,
                        isComplete: true,
                        onReturn: onExit
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DTColor.workspace)
        }
        .onAppear {
            if session.startedCount == 0 {
                session.startedCount = model.inboxMatters.count
            }
        }
        .onChange(of: model.inboxMatters.count) { count in
            if currentIndex >= count {
                currentIndex = max(0, count - 1)
            }
        }
    }

    private var headerDetail: String {
        if shouldShowSummary {
            return session.totalResolved > 0 ? "\(session.totalResolved) cleared" : "done"
        }
        let startedCount = max(session.startedCount, model.inboxMatters.count)
        guard startedCount > 0 else {
            return "ready"
        }
        return "\(min(session.totalResolved + 1, startedCount)) of \(startedCount)"
    }

    private func resolve(_ matter: MatterSnapshot, as status: String) {
        guard model.moveMatter(matter, to: status, navigate: false) else {
            return
        }
        session.record(status)
        DispatchQueue.main.async {
            let count = model.inboxMatters.count
            if currentIndex >= count {
                currentIndex = max(0, count - 1)
            }
        }
    }

    private func finishSession() {
        if shouldShowSummary {
            onExit()
        } else if session.totalResolved > 0 {
            isShowingSummary = true
        } else {
            onExit()
        }
    }
}

private struct ClearHeader: View {
    let detail: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Clear")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
            Spacer()
            QuietHeaderButton(actionTitle) {
                onAction()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private struct ClearMatterFocus: View {
    let matter: MatterSnapshot
    let onDrop: () -> Void
    let onDone: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(matter.text)
                .font(.system(size: 21, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                MatterMetaLine(createdAt: matter.createdAt, source: matter.source)
            }

            Rectangle()
                .fill(Color.black.opacity(0.045))
                .frame(height: 1)

            HStack(spacing: 18) {
                ClearActionButton("Drop", tint: DTColor.dimmed, action: onDrop)
                ClearActionButton("Done", tint: DTColor.green, action: onDone)
                ClearActionButton("Keep", tint: DTColor.green, action: onKeep)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(22)
    }
}

private struct ClearActionButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(isHovered ? tint : DTColor.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.black.opacity(0.035) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct ClearSessionSummaryView: View {
    let summary: ClearSessionSummary
    let isComplete: Bool
    let onReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.system(size: 21, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(detail)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
            }

            Divider().overlay(DTColor.line)

            VStack(spacing: 0) {
                if summary.actionRows.isEmpty {
                    SummaryLine(title: "Cleared", value: "0", tint: DTColor.dimmed)
                } else {
                    ForEach(Array(summary.actionRows.enumerated()), id: \.offset) { index, row in
                        SummaryLine(title: row.title, value: "\(row.count)", tint: row.tint)
                        if index < summary.actionRows.count - 1 {
                            Rectangle()
                                .fill(Color.black.opacity(0.055))
                                .frame(height: 1)
                        }
                    }
                }
            }

            if !isComplete && summary.remainingCount > 0 {
                Text("\(summary.remainingCount) still waiting in Inbox.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
            }

            HStack {
                Spacer()
                QuietHeaderButton("Back to Inbox") {
                    onReturn()
                }
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.horizontal, 36)
    }

    private var title: String {
        if summary.totalResolved == 0 {
            return isComplete ? "Inbox is quiet" : "Nothing cleared yet"
        }
        return isComplete ? "Inbox is quiet" : "Clear session finished"
    }

    private var detail: String {
        if summary.totalResolved == 0 {
            return isComplete ? "Nothing else is asking for your attention here." : "No matters were moved this time."
        }
        let noun = summary.totalResolved == 1 ? "matter" : "matters"
        return "\(summary.totalResolved) \(noun) cleared from attention."
    }
}

private struct SummaryLine: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 9)
    }
}
