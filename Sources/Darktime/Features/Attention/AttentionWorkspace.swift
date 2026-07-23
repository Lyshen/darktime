import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct AttentionWorkspace: View {
    @ObservedObject var model: DashboardModel
    @State private var mode: AttentionMode = .items
    @State private var lens: AttentionLens = .current
    @State private var timelineRange: AttentionTimelineRange = .thirtyDays

    private var visibleRepos: [LocalRepoSnapshot] {
        model.localRepoSnapshots.filter { lens.includes(repo: $0) }
    }

    private var visibleIssues: [MatterSnapshot] {
        switch lens {
        case .current:
            return model.issueMatters.filter { attentionIssueState(for: $0) == "open" }
        case .fading:
            return model.issueMatters.filter { attentionIssueState(for: $0) == "stale" }
        case .inactive:
            return []
        case .all:
            return model.issueMatters
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AttentionTopBar(
                model: model,
                mode: $mode,
                lens: $lens,
                timelineRange: $timelineRange
            )
            Divider().overlay(DTColor.line.opacity(0.7))

            switch mode {
            case .items:
                AttentionItemsView(
                    model: model,
                    lens: lens,
                    visibleRepos: visibleRepos,
                    visibleIssues: visibleIssues,
                    emptyTitle: emptyTitle,
                    emptyDetail: emptyDetail
                )
            case .timeline:
                AttentionTimelineWorkspace(
                    repos: model.localRepoSnapshots,
                    actions: model.actions,
                    range: timelineRange
                )
            }
        }
        .background(DTColor.workspace)
    }

    private var emptyTitle: String {
        switch lens {
        case .current: return "No active attention"
        case .fading: return "No fading items"
        case .inactive: return "No inactive projects"
        case .all: return "No issues or projects yet"
        }
    }

    private var emptyDetail: String {
        switch lens {
        case .current: return "Clear Inbox into issues, or add a local repo as a project."
        case .fading: return "Issues and projects show up here when they start to drift."
        case .inactive: return "Inactive projects stay out of sight until you choose to review them."
        case .all: return "Clear Inbox into issues, or add a local repo as a project."
        }
    }
}

private struct AttentionItemsView: View {
    @ObservedObject var model: DashboardModel
    let lens: AttentionLens
    let visibleRepos: [LocalRepoSnapshot]
    let visibleIssues: [MatterSnapshot]
    let emptyTitle: String
    let emptyDetail: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if visibleRepos.isEmpty && visibleIssues.isEmpty {
                    EmptyStateLine(
                        systemImage: "scope",
                        title: emptyTitle,
                        detail: emptyDetail
                    )
                } else {
                    if !visibleRepos.isEmpty {
                        AttentionSectionTitle("Projects")
                        VStack(spacing: 0) {
                            ForEach(visibleRepos, id: \.project.id) { repo in
                                LocalRepoProjectRow(model: model, repo: repo, lens: lens)
                                if repo.project.id != visibleRepos.last?.project.id {
                                    AttentionHairline()
                                }
                            }
                        }
                    }

                    if !visibleIssues.isEmpty {
                        AttentionSectionTitle("Issues")
                        VStack(spacing: 0) {
                            ForEach(visibleIssues, id: \.id) { matter in
                                IssueRow(model: model, matter: matter)
                                if matter.id != visibleIssues.last?.id {
                                    AttentionHairline()
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 42)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
    }
}

private struct AttentionTopBar: View {
    @ObservedObject var model: DashboardModel
    @Binding var mode: AttentionMode
    @Binding var lens: AttentionLens
    @Binding var timelineRange: AttentionTimelineRange

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Attention")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Spacer()
            ProjectActionSyncStatus(model: model)
            AttentionModeSwitch(selection: $mode)
            if mode == .items {
                AttentionLensMenu(selection: $lens)
            } else {
                AttentionTimelineRangePicker(selection: $timelineRange)
            }
            QuietHeaderButton("Add Repo") {
                model.addLocalRepoProject()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private struct ProjectActionSyncStatus: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        if shouldShow {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .regular, design: .default))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.055), lineWidth: 1)
            )
            .help(helpText)
        }
    }

    private var shouldShow: Bool {
        model.isSyncingActions ||
            model.actionSyncError != nil ||
            model.actionSyncLastFinishedAt != nil ||
            !model.localRepoSnapshots.isEmpty
    }

    private var label: String {
        if model.isSyncingActions {
            return "Syncing"
        }
        if model.actionSyncError != nil {
            return "Sync failed"
        }
        if let lastFinishedAt = model.actionSyncLastFinishedAt {
            return "Synced \(formatRelative(lastFinishedAt))"
        }
        return "Not synced"
    }

    private var helpText: String {
        if let error = model.actionSyncError {
            return error
        }
        if model.isSyncingActions {
            return "Syncing local git actions."
        }
        if let lastFinishedAt = model.actionSyncLastFinishedAt {
            return "Last sync \(formatLocalDateTime(lastFinishedAt)). \(model.actionSyncLastChangeCount) actions changed."
        }
        return "Local git actions have not synced yet."
    }

    private var systemImage: String {
        if model.isSyncingActions {
            return "arrow.triangle.2.circlepath"
        }
        if model.actionSyncError != nil {
            return "exclamationmark.triangle"
        }
        return "checkmark.circle"
    }

    private var tint: Color {
        if model.isSyncingActions {
            return DTColor.cyan
        }
        if model.actionSyncError != nil {
            return DTColor.amber
        }
        return DTColor.dimmed
    }
}

private enum AttentionMode: String, CaseIterable, Identifiable {
    case items = "Items"
    case timeline = "Timeline"

    var id: String { rawValue }
}

enum AttentionLens: String, CaseIterable, Identifiable {
    case current = "Current"
    case fading = "Fading"
    case inactive = "Inactive"
    case all = "All"

    var id: String { rawValue }

    func includes(repo: LocalRepoSnapshot) -> Bool {
        switch self {
        case .current:
            return repo.state == "alive" || repo.state == "quiet" || repo.state == "empty"
        case .fading:
            return repo.state == "fading"
        case .inactive:
            return repo.state == "inactive"
        case .all:
            return true
        }
    }
}

private struct AttentionModeSwitch: View {
    @Binding var selection: AttentionMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AttentionMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(selection == mode ? DTColor.text : DTColor.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selection == mode ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.045))
        )
    }
}

private struct AttentionLensMenu: View {
    @Binding var selection: AttentionLens

    var body: some View {
        Menu {
            ForEach(AttentionLens.allCases) { lens in
                Button {
                    selection = lens
                } label: {
                    if selection == lens {
                        Label(lens.rawValue, systemImage: "checkmark")
                    } else {
                        Text(lens.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .regular))
            }
            .foregroundStyle(DTColor.text)
            .frame(width: 28, height: 25)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct AttentionSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(DTColor.dimmed)
        .padding(.bottom, 2)
    }
}
