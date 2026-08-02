import Foundation
import SwiftUI

struct DailyStartTodaySheet: View {
    @ObservedObject var model: DashboardModel
    let onPickExisting: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""
    @State private var drafts: [DailyStartIssueDraft] = []
    @State private var errorMessage: String?

    init(model: DashboardModel, onPickExisting: @escaping () -> Void) {
        self.model = model
        self.onPickExisting = onPickExisting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start Today")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text("What is on your mind today?")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
            }

            if drafts.isEmpty {
                inputBox
            } else {
                draftList
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Pick existing issue") {
                    onPickExisting()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if drafts.isEmpty {
                    Button("Extract") {
                        extract()
                    }
                    .disabled(!canExtract)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Add to Today") {
                        addToToday()
                    }
                    .disabled(!canAddToToday)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(DTColor.workspace)
    }

    private var inputBox: some View {
        TextEditor(text: $inputText)
            .font(.system(size: 14, weight: .regular, design: .default))
            .frame(minHeight: 128)
            .padding(8)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
    }

    private var draftList: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach($drafts) { $draft in
                    DailyStartDraftRow(
                        title: $draft.title,
                        projectId: $draft.projectId,
                        projects: model.projects,
                        autoPublishProjectIds: autoPublishProjectIds,
                        onRemove: {
                            removeDraft(id: draft.id)
                        }
                    )
                    if draft.id != drafts.last?.id {
                        DailyHairline()
                    }
                }
            }

            Button("Back to input") {
                drafts = []
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .regular, design: .default))
            .foregroundStyle(DTColor.muted)
        }
    }

    private var canExtract: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddToToday: Bool {
        drafts.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func extract() {
        let titles = extractStartTodayIssueTitles(from: inputText)
        drafts = titles.map { DailyStartIssueDraft(title: $0) }
        errorMessage = drafts.isEmpty ? "Write one thing first." : nil
    }

    private func addToToday() {
        let draftsToCreate = drafts.compactMap { draft -> DailyStartIssueDraft? in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                return nil
            }
            return DailyStartIssueDraft(id: draft.id, title: title, projectId: draft.projectId)
        }

        guard !draftsToCreate.isEmpty else {
            errorMessage = "Keep at least one issue."
            return
        }

        for draft in draftsToCreate {
            if let project = project(for: draft) {
                let publishToGitHub = model.canPublishIssuesToGitHub(project) && model.shouldPublishNewIssuesToGitHub(project)
                guard model.createProjectIssueForToday(project, text: draft.title, publishToGitHub: publishToGitHub) else {
                    errorMessage = model.storageError ?? "Could not add issue."
                    return
                }
            } else if !model.createIssueForToday(text: draft.title) {
                errorMessage = model.storageError ?? "Could not add issue."
                return
            }
        }

        dismiss()
    }

    private func removeDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    private func project(for draft: DailyStartIssueDraft) -> ProjectSnapshot? {
        guard let projectId = draft.projectId else {
            return nil
        }
        return model.projects.first { $0.id == projectId }
    }

    private var autoPublishProjectIds: Set<String> {
        Set(model.projects
            .filter { model.canPublishIssuesToGitHub($0) && model.shouldPublishNewIssuesToGitHub($0) }
            .map(\.id))
    }
}

private struct DailyStartIssueDraft: Identifiable {
    var id = UUID()
    var title: String
    var projectId: String?
}

private struct DailyStartDraftRow: View {
    @Binding var title: String
    @Binding var projectId: String?
    let projects: [ProjectSnapshot]
    let autoPublishProjectIds: Set<String>
    let onRemove: () -> Void
    @State private var isHovered = false
    @State private var isEditing = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 16)

            if isEditing {
                TextField("Issue", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                    .focused($isTitleFocused)
                    .onSubmit {
                        isEditing = false
                    }
            } else {
                Text(title)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        beginEditing()
                    }
            }

            ProjectPickerMenu(
                projectId: $projectId,
                projects: projects,
                autoPublishProjectIds: autoPublishProjectIds
            )

            if autoPublishesToGitHub {
                Text("GitHub")
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }

            Button {
                beginEditing()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DTColor.dimmed)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isEditing ? 1 : 0)
            .help("Edit")

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DTColor.dimmed)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isEditing ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.black.opacity(0.018) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: isEditing) { editing in
            if editing {
                isTitleFocused = true
            }
        }
    }

    private var autoPublishesToGitHub: Bool {
        guard let projectId else {
            return false
        }
        return autoPublishProjectIds.contains(projectId)
    }

    private func beginEditing() {
        isEditing = true
        isTitleFocused = true
    }
}

private struct ProjectPickerMenu: View {
    @Binding var projectId: String?
    let projects: [ProjectSnapshot]
    let autoPublishProjectIds: Set<String>

    var body: some View {
        Menu {
            Button {
                projectId = nil
            } label: {
                if projectId == nil {
                    Label("No project", systemImage: "checkmark")
                } else {
                    Text("No project")
                }
            }

            if !projects.isEmpty {
                Divider()
            }

            ForEach(projects, id: \.id) { project in
                Button {
                    projectId = project.id
                } label: {
                    let title = autoPublishProjectIds.contains(project.id) ? "\(project.title) · GitHub" : project.title
                    if projectId == project.id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Text(projectTitle)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(projectId == nil ? DTColor.dimmed : DTColor.muted)
                .lineLimit(1)
                .frame(width: 116, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Link project")
    }

    private var projectTitle: String {
        guard
            let projectId,
            let project = projects.first(where: { $0.id == projectId })
        else {
            return "No project"
        }
        return project.title
    }
}

private func extractStartTodayIssueTitles(from text: String) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return []
    }

    let prepared = preparedStartTodayInput(trimmed)
    let titles = prepared
        .components(separatedBy: .newlines)
        .map(cleanStartTodayLine)
        .filter { !$0.isEmpty }

    let uniqueTitles = uniqueStartTodayTitles(titles)
    if !uniqueTitles.isEmpty {
        return Array(uniqueTitles.prefix(6))
    }

    return [normalizedStartTodayWhitespace(trimmed)]
}

private func preparedStartTodayInput(_ text: String) -> String {
    var prepared = text
        .replacingOccurrences(of: "；", with: "\n")
        .replacingOccurrences(of: ";", with: "\n")

    prepared = replacingMatches(
        in: prepared,
        pattern: #"(?m)^\s*[-*•]\s+"#,
        with: "\n"
    )
    prepared = replacingMatches(
        in: prepared,
        pattern: #"(?m)^\s*\d{1,2}[\.\)、\)]\s*"#,
        with: "\n"
    )
    prepared = replacingMatches(
        in: prepared,
        pattern: #"\s+\d{1,2}[\.\)、\)]\s*"#,
        with: "\n"
    )

    return prepared
}

private func cleanStartTodayLine(_ line: String) -> String {
    var cleaned = normalizedStartTodayWhitespace(line)

    for prefix in ["- ", "* ", "• "] where cleaned.hasPrefix(prefix) {
        cleaned.removeFirst(prefix.count)
        return normalizedStartTodayWhitespace(cleaned)
    }

    var digitCount = 0
    for character in cleaned {
        if character.isNumber {
            digitCount += 1
        } else {
            break
        }
    }

    if digitCount > 0 && digitCount < cleaned.count {
        let markerIndex = cleaned.index(cleaned.startIndex, offsetBy: digitCount)
        if [".", ")", "）", "、"].contains(String(cleaned[markerIndex])) {
            let titleStart = cleaned.index(after: markerIndex)
            cleaned = String(cleaned[titleStart...])
        }
    }

    return normalizedStartTodayWhitespace(cleaned)
}

private func normalizedStartTodayWhitespace(_ value: String) -> String {
    value
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func uniqueStartTodayTitles(_ titles: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []

    for title in titles {
        let key = title.lowercased()
        guard !seen.contains(key) else {
            continue
        }
        seen.insert(key)
        result.append(title)
    }

    return result
}

private func replacingMatches(in value: String, pattern: String, with template: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return value
    }

    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
}
