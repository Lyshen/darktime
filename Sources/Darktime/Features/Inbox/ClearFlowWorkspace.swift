import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct ClearFlowWorkspace: View {
    @ObservedObject var model: DashboardModel
    let onExit: () -> Void
    @State private var currentIndex = 0

    private var currentMatter: MatterSnapshot? {
        let matters = model.inboxMatters
        guard !matters.isEmpty else {
            return nil
        }
        return matters[min(currentIndex, matters.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            ClearHeader(
                current: currentPosition,
                total: model.inboxMatters.count,
                onExit: onExit
            )
            Divider().overlay(DTColor.line.opacity(0.7))

            ZStack {
                if let matter = currentMatter {
                    ClearMatterCard(
                        matter: matter,
                        onDrop: { resolve(matter, as: "dropped") },
                        onLater: { resolve(matter, as: "later") },
                        onDone: { resolve(matter, as: "done") },
                        onRootbox: { resolve(matter, as: "rootbox") }
                    )
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 36)
                } else {
                    ClearCompleteView(onExit: onExit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DTColor.workspace)
        }
        .onChange(of: model.inboxMatters.count) { count in
            if currentIndex >= count {
                currentIndex = max(0, count - 1)
            }
        }
    }

    private var currentPosition: Int {
        guard !model.inboxMatters.isEmpty else {
            return 0
        }
        return min(currentIndex + 1, model.inboxMatters.count)
    }

    private func resolve(_ matter: MatterSnapshot, as status: String) {
        model.moveMatter(matter, to: status)
        DispatchQueue.main.async {
            let count = model.inboxMatters.count
            if currentIndex >= count {
                currentIndex = max(0, count - 1)
            }
        }
    }
}

private struct ClearHeader: View {
    let current: Int
    let total: Int
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Clear")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text(total > 0 ? "\(current) of \(total)" : "done")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
            Spacer()
            QuietHeaderButton("Exit") {
                onExit()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private struct ClearMatterCard: View {
    let matter: MatterSnapshot
    let onDrop: () -> Void
    let onLater: () -> Void
    let onDone: () -> Void
    let onRootbox: () -> Void

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

            Divider().overlay(DTColor.line)

            HStack(spacing: 10) {
                clearAction("Drop", "xmark", tint: DTColor.dimmed, action: onDrop)
                clearAction("Later", "clock", tint: DTColor.cyan, action: onLater)
                clearAction("Done", "checkmark", tint: DTColor.green, action: onDone)
                clearAction("Rootbox", "tree", tint: DTColor.green, action: onRootbox)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.024))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.09), lineWidth: 1)
        )
    }

    private func clearAction(_ title: String, _ image: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(tint)
    }
}

private struct ClearCompleteView: View {
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(DTColor.green)
            Text("Inbox is clear")
                .font(.system(size: 20, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text)
            Text("Nothing else is asking for your attention here.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
            Button {
                onExit()
            } label: {
                Text("Back to Inbox")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(DTColor.text)
            .padding(.top, 4)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 36)
    }
}
