import Foundation
import SwiftUI

struct IssueRow: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var isAttaching = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(issueTint)
                .frame(width: 28, height: 28)
                .background(issueTint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(matter.text)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if let projectTitle = model.projectTitle(for: matter) {
                        Text(projectTitle)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.text.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }

                HStack {
                    IssueKindText(kind: matter.issueKind)
                    Spacer()
                }

                HStack {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        IssueActivityMetaGroup(
                            time: formatRelative(matter.updatedAt),
                            state: issueState,
                            tint: issueTint
                        )
                        .opacity(isHovering ? 0 : 1)

                        HStack(spacing: 2) {
                            AttentionRowActionButton("Edit") {
                                isEditing = true
                            }
                            if matter.projectId == nil {
                                AttentionRowActionButton("Attach") {
                                    isAttaching = true
                                }
                            } else {
                                AttentionRowActionButton("Detach") {
                                    model.detachIssue(matter)
                                }
                            }
                            AttentionRowActionButton("Make Project") {
                                model.linkIssueToLocalRepoProject(matter)
                            }
                            AttentionRowActionButton("Drop") {
                                model.moveMatter(matter, to: "dropped")
                            }
                        }
                        .opacity(isHovering ? 1 : 0)
                        .allowsHitTesting(isHovering)
                    }
                    .animation(.easeOut(duration: 0.12), value: isHovering)
                }
                .frame(height: 19)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .sheet(isPresented: $isEditing) {
            IssueEditSheet(model: model, issue: matter)
        }
        .sheet(isPresented: $isAttaching) {
            IssueProjectAttachSheet(model: model, issue: matter)
        }
    }

    private var issueState: String {
        attentionIssueState(for: matter)
    }

    private var issueTint: Color {
        issueState == "stale" ? DTColor.dimmed : DTColor.amber
    }

}

private struct IssueKindText: View {
    let kind: String?

    var body: some View {
        Text(displayKind)
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(DTColor.dimmed)
    }

    private var displayKind: String {
        switch kind {
        case "github_pr":
            return "github pr"
        case "github_issue":
            return "github issue"
        default:
            return "manual"
        }
    }
}

private struct IssueProjectAttachSheet: View {
    @ObservedObject var model: DashboardModel
    let issue: MatterSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectId: String?
    @State private var errorMessage: String?

    init(model: DashboardModel, issue: MatterSnapshot) {
        self.model = model
        self.issue = issue
        _selectedProjectId = State(initialValue: model.projects.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Attach Issue")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(issue.text)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(2)
            }

            Picker("Project", selection: $selectedProjectId) {
                ForEach(model.projects, id: \.id) { project in
                    Text(project.title).tag(Optional(project.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Attach") {
                    attach()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProjectId == nil)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func attach() {
        guard
            let selectedProjectId,
            let project = model.projects.first(where: { $0.id == selectedProjectId })
        else {
            return
        }

        let ok = model.attachIssue(issue, to: project)
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct IssueEditSheet: View {
    @ObservedObject var model: DashboardModel
    let issue: MatterSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var errorMessage: String?

    init(model: DashboardModel, issue: MatterSnapshot) {
        self.model = model
        self.issue = issue
        _text = State(initialValue: issue.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Issue")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text("Keep the wording clear enough to return to it.")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .frame(height: 120)
                .padding(6)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func save() {
        let ok = model.updateIssue(issue, text: text)
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct IssueActivityMetaGroup: View {
    let time: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(time)
            Text("·")
                .foregroundStyle(DTColor.dimmed.opacity(0.75))
            ProjectActivityTag(text: state, tint: tint)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }
}

func attentionIssueState(for matter: MatterSnapshot) -> String {
    guard let date = parseISODate(matter.updatedAt) else {
        return "open"
    }
    return Date().timeIntervalSince(date) > 7 * 86_400 ? "stale" : "open"
}

func formatAttentionTime(_ isoString: String, lens: AttentionLens) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    if lens == .current || Calendar.current.isDateInToday(date) {
        return formatAttentionRelative(date)
    }

    let days = max(1, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 1)
    return "\(days)d ago · \(formatAttentionMonthDay(date))"
}

private func formatAttentionRelative(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 {
        return "now"
    }
    if seconds < 3600 {
        return "\(seconds / 60)m ago"
    }
    if seconds < 86_400 {
        return "\(seconds / 3600)h ago"
    }

    let days = max(1, seconds / 86_400)
    return "\(days)d ago"
}

private func formatAttentionMonthDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

struct AttentionHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(height: 1)
    }
}
