import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct DailyFocusWorkspace: View {
    @ObservedObject var model: DashboardModel

    private var candidateIssues: [MatterSnapshot] {
        model.issueMatters
            .filter { $0.externalState?.lowercased() != "closed" }
            .sorted { left, right in
                let leftFocused = model.isDailyFocus(left)
                let rightFocused = model.isDailyFocus(right)
                if leftFocused != rightFocused {
                    return leftFocused
                }
                return left.updatedAt > right.updatedAt
            }
    }

    private var todayActions: [ActionSnapshot] {
        model.todayActions.sorted { $0.happenedAt > $1.happenedAt }
    }

    private var todayActionSections: [DailyActionProjectSection] {
        Dictionary(grouping: todayActions, by: \.projectId)
            .map { projectId, actions in
                DailyActionProjectSection(
                    projectId: projectId,
                    title: model.projectTitle(projectId: projectId) ?? "Unknown project",
                    actions: actions.sorted { $0.happenedAt > $1.happenedAt }
                )
            }
            .sorted { left, right in
                left.latestActionAt > right.latestActionAt
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            DailyFocusHeader(
                focusCount: model.dailyFocusIssueIDs.count,
                actionCount: todayActions.count,
                onClear: model.clearDailyFocus
            )
            Divider().overlay(DTColor.line.opacity(0.7))

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    DailyFocusSectionTitle("Focus")
                    if candidateIssues.isEmpty {
                        DailyEmptyLine(
                            systemImage: "circle.dotted",
                            title: "No issues yet",
                            detail: "Create project issues from Attention to plan the day."
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(candidateIssues, id: \.id) { issue in
                                DailyIssueFocusRow(
                                    model: model,
                                    issue: issue,
                                    isFocused: model.isDailyFocus(issue)
                                )
                                if issue.id != candidateIssues.last?.id {
                                    DailyHairline()
                                }
                            }
                        }
                    }

                    DailyFocusSectionTitle("Actions Today")
                    if todayActions.isEmpty {
                        DailyEmptyLine(
                            systemImage: "bolt",
                            title: "No actions today",
                            detail: "Commits and future action sources will appear here."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(todayActionSections) { section in
                                DailyActionProjectGroup(section: section)
                            }
                        }
                    }

                    DailyFocusSectionTitle("End Note")
                    DailyReflectionEditor(text: $model.dailyReflection)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 42)
                .padding(.top, 28)
                .padding(.bottom, 44)
            }
        }
        .background(DTColor.workspace)
    }
}

private struct DailyActionProjectSection: Identifiable {
    let projectId: String
    let title: String
    let actions: [ActionSnapshot]

    var id: String { projectId }

    var latestActionAt: String {
        actions.first?.happenedAt ?? ""
    }
}

private struct DailyFocusHeader: View {
    let focusCount: Int
    let actionCount: Int
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sun.max")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Today")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text("\(focusCount) focus · \(actionCount) actions")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .lineLimit(1)
            Spacer()
            QuietHeaderButton("Clear Focus", isEnabled: focusCount > 0) {
                onClear()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private struct DailyIssueFocusRow: View {
    @ObservedObject var model: DashboardModel
    let issue: MatterSnapshot
    let isFocused: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            model.toggleDailyFocus(issue)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isFocused ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(isFocused ? DTColor.green : DTColor.dimmed)
                    .frame(width: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(issue.text)
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.text)
                            .fixedSize(horizontal: false, vertical: true)

                        if let projectTitle = model.projectTitle(for: issue) {
                            Text(projectTitle)
                                .font(.system(size: 12, weight: .regular, design: .default))
                                .foregroundStyle(DTColor.text.opacity(0.5))
                                .lineLimit(1)
                        }
                    }

                    Text(issueKindText(issue.issueKind))
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.dimmed)
                }

                Spacer(minLength: 12)
                Text(formatRelative(issue.updatedAt))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered ? Color.black.opacity(0.018) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct DailyActionProjectGroup: View {
    let section: DailyActionProjectSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DTColor.cyan)
                    .frame(width: 18)

                Text(section.title)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(DTColor.text)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(section.actions.count == 1 ? "1 action" : "\(section.actions.count) actions")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(section.actions.enumerated()), id: \.element.id) { index, action in
                    DailyActionRow(action: action)
                    if index < section.actions.count - 1 {
                        DailyHairline()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyActionRow: View {
    let action: ActionSnapshot
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: actionIcon)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DTColor.cyan)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 7) {
                Text(action.summary ?? action.kind)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(actionKindText(action.kind))
                    Text(actionSourceText(action.source))
                    Text(formatLocalTime(action.happenedAt))
                }
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.black.opacity(0.018) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var actionIcon: String {
        switch action.kind {
        case "commit":
            return "arrow.triangle.branch"
        default:
            return "bolt"
        }
    }
}

private struct DailyReflectionEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14, weight: .regular, design: .default))
            .frame(minHeight: 96)
            .padding(8)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct DailyFocusSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(DTColor.dimmed)
    }
}

private struct DailyEmptyLine: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
    }
}

private struct DailyHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(height: 1)
            .padding(.horizontal, 8)
    }
}

private func issueKindText(_ kind: String?) -> String {
    switch kind {
    case "github_pr":
        return "github pr"
    case "github_issue":
        return "github issue"
    default:
        return "manual"
    }
}

private func actionKindText(_ kind: String) -> String {
    switch kind {
    case "commit":
        return "commit"
    default:
        return kind.replacingOccurrences(of: "_", with: " ")
    }
}

private func actionSourceText(_ source: String) -> String {
    switch source {
    case "local_git":
        return "local git"
    default:
        return source.replacingOccurrences(of: "_", with: " ")
    }
}
