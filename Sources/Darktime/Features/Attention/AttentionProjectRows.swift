import AppKit
import Foundation
import SwiftUI

struct LocalRepoProjectRow: View {
    @ObservedObject var model: DashboardModel
    let repo: LocalRepoSnapshot
    let lens: AttentionLens
    @State private var isRowHovering = false
    @State private var isTitleHovering = false
    @State private var isEditing = false
    @State private var isCreatingIssue = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(stateTint)
                .frame(width: 28, height: 28)
                .background(stateTint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        model.openLocalRepo(repo)
                    } label: {
                        Text(repo.project.title)
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundStyle(DTColor.text)
                            .underline(isTitleHovering, color: DTColor.text.opacity(0.45))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(2)
                    .onHover { hovering in
                        isTitleHovering = hovering
                    }

                    if let intentionText {
                        Text(intentionText)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.text.opacity(0.5))
                            .lineLimit(1)
                    }

                    if repo.openIssueCount > 0 {
                        Text("\(repo.openIssueCount) issues")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(DTColor.dimmed)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.035))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    Spacer(minLength: 8)
                }

                Text(repo.latestCommitSummary ?? "No commits yet")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
                    .lineLimit(2)

                HStack {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        ProjectActivityMetaGroup(
                            time: timeSummary,
                            count: commitWindowSummary,
                            state: repo.state,
                            tint: stateTint
                        )
                        .opacity(isRowHovering ? 0 : 1)

                        HStack(spacing: 2) {
                            AttentionRowActionButton("Issue") {
                                isCreatingIssue = true
                            }
                            AttentionRowActionButton("Edit") {
                                isEditing = true
                            }
                            AttentionRowActionButton("Remove") {
                                isConfirmingRemoval = true
                            }
                        }
                        .opacity(isRowHovering ? 1 : 0)
                        .allowsHitTesting(isRowHovering)
                    }
                    .animation(.easeOut(duration: 0.12), value: isRowHovering)
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
            isRowHovering = hovering
        }
        .sheet(isPresented: $isEditing) {
            ProjectEditSheet(model: model, project: repo.project)
        }
        .sheet(isPresented: $isCreatingIssue) {
            ProjectIssueCreateSheet(model: model, project: repo.project)
        }
        .alert("Remove project?", isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive) {
                model.removeProject(repo.project)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will not delete the local repository.")
        }
    }

    private var intentionText: String? {
        guard let intention = repo.project.intention?.trimmingCharacters(in: .whitespacesAndNewlines), !intention.isEmpty else {
            return nil
        }
        return intention
    }

    private var stateTint: Color {
        switch repo.state {
        case "alive": return DTColor.green
        case "quiet": return DTColor.cyan
        case "fading": return DTColor.amber
        case "inactive": return DTColor.dimmed
        case "empty": return DTColor.amber
        default: return DTColor.red
        }
    }

    private var timeSummary: String {
        if let lastCommitAt = repo.lastCommitAt {
            return formatAttentionTime(lastCommitAt, lens: lens)
        }
        return "no commits"
    }

    private var commitWindowSummary: String {
        switch repo.state {
        case "alive":
            return "\(repo.commitsLast2Days) in 2d"
        case "quiet":
            return "\(repo.commitsLast7Days) in 7d"
        case "fading", "inactive":
            return "\(repo.commitsLast30Days) in 30d"
        default:
            return "0 in 30d"
        }
    }
}

private struct ProjectIssueCreateSheet: View {
    @ObservedObject var model: DashboardModel
    let project: ProjectSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Issue")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(project.title)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, weight: .regular, design: .default))
                .frame(height: 98)
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

                Button("Create") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func create() {
        let ok = model.createProjectIssue(project, text: text)
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

private struct ProjectActivityMetaGroup: View {
    let time: String
    let count: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(time)
            Text("·")
                .foregroundStyle(DTColor.dimmed.opacity(0.75))
            Text(count)
            ProjectActivityTag(text: state, tint: tint)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }
}

struct ProjectActivityTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold, design: .default))
            .foregroundStyle(tint.opacity(0.9))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(tint.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct ProjectEditSheet: View {
    @ObservedObject var model: DashboardModel
    let project: ProjectSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var intention: String
    @State private var errorMessage: String?

    init(model: DashboardModel, project: ProjectSnapshot) {
        self.model = model
        self.project = project
        _title = State(initialValue: project.title)
        _intention = State(initialValue: project.intention ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Project")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(project.localPath ?? "")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .regular, design: .default))

                TextEditor(text: $intention)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .frame(height: 74)
                    .padding(6)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            }

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
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(DTColor.workspace)
    }

    private func save() {
        let ok = model.updateProject(
            project,
            title: title,
            intention: intention
        )
        if ok {
            dismiss()
        } else {
            errorMessage = model.storageError
        }
    }
}

struct AttentionRowActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(isHovering ? DTColor.text.opacity(0.78) : DTColor.muted)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? Color.black.opacity(0.045) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
