import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct RootboxWorkspace: View {
    @ObservedObject var model: DashboardModel
    @State private var lens: RootboxLens = .current

    private var visibleRepos: [LocalRepoSnapshot] {
        model.localRepoSnapshots.filter { lens.includes(repo: $0) }
    }

    private var visibleSeeds: [MatterSnapshot] {
        switch lens {
        case .current:
            return model.rootboxMatters.filter { rootboxSeedState(for: $0) == "seed" }
        case .fading:
            return model.rootboxMatters.filter { rootboxSeedState(for: $0) == "fading" }
        case .withered:
            return []
        case .all:
            return model.rootboxMatters
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RootboxTopBar(model: model, lens: $lens)
            Divider().overlay(DTColor.line.opacity(0.7))

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if visibleRepos.isEmpty && visibleSeeds.isEmpty {
                        EmptyStateLine(
                            systemImage: "tree",
                            title: emptyTitle,
                            detail: emptyDetail
                        )
                    } else {
                        if !visibleRepos.isEmpty {
                            RootboxSectionTitle("Projects")
                            VStack(spacing: 0) {
                                ForEach(visibleRepos, id: \.root.id) { repo in
                                    LocalRepoRootRow(model: model, repo: repo, lens: lens)
                                    if repo.root.id != visibleRepos.last?.root.id {
                                        RootboxHairline()
                                    }
                                }
                            }
                        }

                        if !visibleSeeds.isEmpty {
                            RootboxSectionTitle("Seeds")
                            VStack(spacing: 0) {
                                ForEach(visibleSeeds, id: \.id) { matter in
                                    SeedRootRow(model: model, matter: matter)
                                    if matter.id != visibleSeeds.last?.id {
                                        RootboxHairline()
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
        .background(DTColor.workspace)
    }

    private var emptyTitle: String {
        switch lens {
        case .current: return "No current roots"
        case .fading: return "No fading roots"
        case .withered: return "No withered roots"
        case .all: return "No roots yet"
        }
    }

    private var emptyDetail: String {
        switch lens {
        case .current: return "Add a local repo or keep a matter from Inbox."
        case .fading: return "Roots will appear here when they start to drift."
        case .withered: return "Old roots stay out of sight until you choose to review them."
        case .all: return "Add a local repo or keep a matter from Inbox."
        }
    }
}

private struct RootboxTopBar: View {
    @ObservedObject var model: DashboardModel
    @Binding var lens: RootboxLens

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tree.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Rootbox")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Spacer()
            RootboxLensMenu(selection: $lens)
            QuietHeaderButton("Add Repo") {
                model.addLocalRepoRoot()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private enum RootboxLens: String, CaseIterable, Identifiable {
    case current = "Current"
    case fading = "Fading"
    case withered = "Withered"
    case all = "All"

    var id: String { rawValue }

    func includes(repo: LocalRepoSnapshot) -> Bool {
        switch self {
        case .current:
            return repo.state == "alive" || repo.state == "quiet" || repo.state == "seed"
        case .fading:
            return repo.state == "fading"
        case .withered:
            return repo.state == "withered"
        case .all:
            return true
        }
    }
}

private struct RootboxLensMenu: View {
    @Binding var selection: RootboxLens

    var body: some View {
        Menu {
            ForEach(RootboxLens.allCases) { lens in
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

private struct RootboxSectionTitle: View {
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

private struct LocalRepoRootRow: View {
    @ObservedObject var model: DashboardModel
    let repo: LocalRepoSnapshot
    let lens: RootboxLens
    @State private var isRowHovering = false
    @State private var isTitleHovering = false
    @State private var isEditing = false
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
                        Text(repo.root.title)
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

                    Spacer(minLength: 8)
                }

                Text(repo.latestCommitSummary ?? "No commits yet")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
                    .lineLimit(2)

                HStack {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        RootActivityMetaGroup(
                            time: timeSummary,
                            count: commitWindowSummary,
                            state: repo.state,
                            tint: stateTint
                        )
                        .opacity(isRowHovering ? 0 : 1)

                        HStack(spacing: 2) {
                            RootboxRowActionButton("Edit") {
                                isEditing = true
                            }
                            RootboxRowActionButton("Remove") {
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
            RootEditSheet(model: model, root: repo.root)
        }
        .alert("Remove from Rootbox?", isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive) {
                model.removeRoot(repo.root)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will not delete the local repository.")
        }
    }

    private var intentionText: String? {
        guard let intention = repo.root.intention?.trimmingCharacters(in: .whitespacesAndNewlines), !intention.isEmpty else {
            return nil
        }
        return intention
    }

    private var stateTint: Color {
        switch repo.state {
        case "alive": return DTColor.green
        case "quiet": return DTColor.cyan
        case "fading": return DTColor.amber
        case "withered": return DTColor.dimmed
        case "seed": return DTColor.amber
        default: return DTColor.red
        }
    }

    private var timeSummary: String {
        if let lastCommitAt = repo.lastCommitAt {
            return formatRootboxTime(lastCommitAt, lens: lens)
        }
        return "no commits"
    }

    private var commitWindowSummary: String {
        switch repo.state {
        case "alive":
            return "\(repo.commitsLast2Days) in 2d"
        case "quiet":
            return "\(repo.commitsLast7Days) in 7d"
        case "fading", "withered":
            return "\(repo.commitsLast30Days) in 30d"
        default:
            return "0 in 30d"
        }
    }
}

private struct RootActivityMetaGroup: View {
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
            RootActivityTag(text: state, tint: tint)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }
}

private struct RootActivityTag: View {
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

private struct RootEditSheet: View {
    @ObservedObject var model: DashboardModel
    let root: RootSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var intention: String
    @State private var errorMessage: String?

    init(model: DashboardModel, root: RootSnapshot) {
        self.model = model
        self.root = root
        _title = State(initialValue: root.title)
        _intention = State(initialValue: root.intention ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Root")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(DTColor.text)
                Text(root.localPath ?? "")
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
        let ok = model.updateRoot(
            root,
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

private struct RootboxRowActionButton: View {
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

private struct SeedRootRow: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(seedTint)
                .frame(width: 28, height: 28)
                .background(seedTint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 7) {
                Text(matter.text)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    ZStack(alignment: .trailing) {
                        SeedActivityMetaGroup(
                            time: formatRelative(matter.updatedAt),
                            state: seedState,
                            tint: seedTint
                        )
                        .opacity(isHovering ? 0 : 1)

                        HStack(spacing: 2) {
                            RootboxRowActionButton("Link Repo") {
                                model.linkSeedToLocalRepo(matter)
                            }
                            RootboxRowActionButton("Drop") {
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
    }

    private var seedState: String {
        rootboxSeedState(for: matter)
    }

    private var seedTint: Color {
        seedState == "fading" ? DTColor.dimmed : DTColor.amber
    }

}

private struct SeedActivityMetaGroup: View {
    let time: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(time)
            Text("·")
                .foregroundStyle(DTColor.dimmed.opacity(0.75))
            RootActivityTag(text: state, tint: tint)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
    }
}

private func rootboxSeedState(for matter: MatterSnapshot) -> String {
    guard let date = parseISODate(matter.updatedAt) else {
        return "seed"
    }
    return Date().timeIntervalSince(date) > 7 * 86_400 ? "fading" : "seed"
}

private func formatRootboxTime(_ isoString: String, lens: RootboxLens) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    if lens == .current || Calendar.current.isDateInToday(date) {
        return formatRootboxRelative(date)
    }

    let days = max(1, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 1)
    return "\(days)d ago · \(formatRootboxMonthDay(date))"
}

private func formatRootboxRelative(_ date: Date) -> String {
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

private func formatRootboxMonthDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

private struct RootboxHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(height: 1)
    }
}
