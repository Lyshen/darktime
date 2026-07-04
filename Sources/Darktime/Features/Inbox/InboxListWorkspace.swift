import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct InboxListWorkspace: View {
    @ObservedObject var model: DashboardModel
    let onStartClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            InboxHeader(
                count: model.inboxMatters.count,
                canStartClear: !model.inboxMatters.isEmpty,
                onStartClear: onStartClear
            )
            Divider().overlay(DTColor.line.opacity(0.7))

            ScrollView {
                VStack(spacing: 0) {
                    if model.inboxMatters.isEmpty {
                        EmptyStateLine(
                            systemImage: "tray",
                            title: "Inbox is clear",
                            detail: "Use quick capture to unload the next open loop."
                        )
                        .padding(.top, 34)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.inboxMatters.enumerated()), id: \.element.id) { index, matter in
                                InboxMatterLine(
                                    matter: matter,
                                    isLast: index == model.inboxMatters.count - 1
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 660)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
                .padding(.top, 20)
                .padding(.bottom, 36)
            }
        }
    }
}

private struct InboxHeader: View {
    let count: Int
    let canStartClear: Bool
    let onStartClear: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tray.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Inbox")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text(count == 1 ? "1 open loop" : "\(count) open loops")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .lineLimit(1)
            Spacer()
            QuietHeaderButton("Clear", isEnabled: canStartClear) {
                onStartClear()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private struct InboxMatterLine: View {
    let matter: MatterSnapshot
    let isLast: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text(matter.text)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer(minLength: 16)
                    MatterMetaLine(createdAt: matter.createdAt, source: matter.source)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.black.opacity(0.018) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }

            if !isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.055))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
            }
        }
    }
}
