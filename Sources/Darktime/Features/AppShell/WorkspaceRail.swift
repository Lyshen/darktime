import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct WorkspaceRail: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            railButton(for: .capture)

            VStack(alignment: .leading, spacing: 6) {
                railButton(for: .today)
                railButton(for: .inbox)
                railButton(for: .attention)
            }
            .padding(.top, 26)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 54)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DTColor.sidebar)
    }

    private func railButton(for section: WorkspaceSection) -> some View {
        RailItemButton(
            section: section,
            isSelected: model.selectedSection == section,
            count: count(for: section)
        ) {
            model.selectSection(section)
        }
    }

    private func count(for section: WorkspaceSection) -> Int? {
        switch section {
        case .capture: return nil
        case .today: return model.dailyFocusIssueIDs.count
        case .inbox: return model.inboxMatters.count
        case .attention: return model.attentionItemCount
        case .dropped: return nil
        case .shortcutCapture: return nil
        case .calendar: return nil
        }
    }
}

struct RailItemButton: View {
    let section: WorkspaceSection
    let isSelected: Bool
    let count: Int?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 15, weight: .regular, design: .default))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(isSelected ? DTColor.text : DTColor.dimmed)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DTColor.workspace.opacity(0.78))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? DTColor.text : DTColor.muted)
            .background(isSelected || isHovering ? DTColor.sidebarSelection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
