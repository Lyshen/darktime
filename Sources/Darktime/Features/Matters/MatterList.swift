import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct MatterList: View {
    let matters: [MatterSnapshot]
    let emptyTitle: String
    let emptyDetail: String
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if matters.isEmpty {
                    EmptyStateLine(systemImage: "tray", title: emptyTitle, detail: emptyDetail)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(matters, id: \.id) { matter in
                            MatterRow(model: model, matter: matter)
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .background(DTColor.workspace)
    }
}

struct MatterRow: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: matter.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint(for: matter.status))
                    .frame(width: 30, height: 30)
                    .background(tint(for: matter.status).opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 5) {
                    Text(matter.text)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        TinyTag(text: matter.status, tint: tint(for: matter.status))
                        Text(matter.source)
                            .font(.system(size: 11))
                            .foregroundStyle(DTColor.dimmed)
                        Text(formatRelative(matter.updatedAt))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DTColor.dimmed)
                    }
                }
                Spacer()
            }
            if matter.status == "issue" {
                IssueActionBar(model: model, matter: matter)
            } else {
                InboxClearActionBar(model: model, matter: matter)
            }
        }
        .padding(12)
        .background(DTColor.row)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(DTColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func icon(for status: String) -> String {
        switch status {
        case "issue": return "circle.dotted"
        case "today": return "sun.max.fill"
        case "later": return "clock.fill"
        case "done": return "checkmark.circle.fill"
        case "dropped": return "xmark.circle.fill"
        default: return "tray.fill"
        }
    }

    private func tint(for status: String) -> Color {
        switch status {
        case "issue": return DTColor.green
        case "today": return DTColor.amber
        case "later": return DTColor.cyan
        case "done": return DTColor.green
        case "dropped": return DTColor.dimmed
        default: return DTColor.cyan
        }
    }
}

