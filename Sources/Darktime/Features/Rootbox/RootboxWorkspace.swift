import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct RootboxWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            RootboxTopBar(model: model)
            Divider().overlay(DTColor.line.opacity(0.7))

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    RootboxIntroLine()

                    if model.localRepoSnapshots.isEmpty && model.rootboxMatters.isEmpty {
                        EmptyStateLine(
                            systemImage: "tree",
                            title: "Rootbox is empty",
                            detail: "Add a local repo or keep a matter from Inbox to see what is trying to grow."
                        )
                    } else {
                        if !model.localRepoSnapshots.isEmpty {
                            RootboxSectionTitle(
                                title: "Repo roots",
                                detail: "Roots with local project traces."
                            )
                            VStack(spacing: 0) {
                                ForEach(model.localRepoSnapshots, id: \.root.id) { repo in
                                    LocalRepoRootRow(model: model, repo: repo)
                                    if repo.root.id != model.localRepoSnapshots.last?.root.id {
                                        RootboxHairline()
                                    }
                                }
                            }
                        }

                        if !model.rootboxMatters.isEmpty {
                            RootboxSectionTitle(
                                title: "Seeds",
                                detail: "Kept matters that have not grown external traces yet."
                            )
                            VStack(spacing: 0) {
                                ForEach(model.rootboxMatters, id: \.id) { matter in
                                    SeedRootRow(model: model, matter: matter)
                                    if matter.id != model.rootboxMatters.last?.id {
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
}

private struct RootboxTopBar: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tree.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Rootbox")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text("Roots with real traces and seeds worth watching.")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            QuietHeaderButton("Refresh") {
                model.refreshRepoRoots()
            }
            QuietHeaderButton("Add Repo") {
                model.addLocalRepoRoot()
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }
}

private struct RootboxIntroLine: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What is actually alive?")
                .font(.system(size: 21, weight: .regular, design: .default))
                .foregroundStyle(DTColor.text)
            Text("Repo roots show recent action. Seeds are kept ideas still waiting for roots.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RootboxSectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
        }
        .padding(.bottom, 2)
    }
}

private struct LocalRepoRootRow: View {
    @ObservedObject var model: DashboardModel
    let repo: LocalRepoSnapshot

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
                    Text(repo.repoName)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(DTColor.text)
                        .lineLimit(1)
                    RootStateTag(text: repo.state, tint: stateTint)
                    Spacer()
                    Text(actionSummary)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(DTColor.dimmed)
                        .lineLimit(1)
                }

                Text(repo.latestCommitSummary ?? "No commits yet")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Text(repo.branch)
                    Text("\(repo.commitsLast7Days) in 7d")
                    Text("\(repo.commitsLast30Days) in 30d")
                    if repo.hasUncommittedChanges {
                        Text("local changes")
                            .foregroundStyle(DTColor.amber)
                    }
                    Spacer()
                    Button("Open") {
                        model.openLocalRepo(repo)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DTColor.muted)
                }
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 13)
    }

    private var stateTint: Color {
        switch repo.state {
        case "alive": return DTColor.green
        case "quiet": return DTColor.cyan
        case "stale": return DTColor.dimmed
        case "seed": return DTColor.amber
        default: return DTColor.red
        }
    }

    private var actionSummary: String {
        if repo.hasUncommittedChanges {
            return "working now"
        }
        if let lastCommitAt = repo.lastCommitAt {
            return formatRelative(lastCommitAt)
        }
        return "no commits"
    }
}

private struct SeedRootRow: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(seedTint)
                .frame(width: 28, height: 28)
                .background(seedTint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(matter.text)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    RootStateTag(text: seedState, tint: seedTint)
                    Spacer()
                    Text(formatRelative(matter.updatedAt))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(DTColor.dimmed)
                }

                Text(seedDetail)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.muted)

                HStack(spacing: 14) {
                    Button("Move to Inbox") {
                        model.moveMatter(matter, to: "inbox")
                    }
                    Button("Drop") {
                        model.moveMatter(matter, to: "dropped")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
            }
        }
        .padding(.vertical, 13)
    }

    private var seedState: String {
        guard let date = parseISODate(matter.updatedAt) else {
            return "seed"
        }
        return Date().timeIntervalSince(date) > 7 * 86_400 ? "fading" : "seed"
    }

    private var seedTint: Color {
        seedState == "fading" ? DTColor.dimmed : DTColor.amber
    }

    private var seedDetail: String {
        seedState == "fading"
            ? "No external trace yet. Still worth keeping?"
            : "Kept from Inbox. It has not grown a repo root yet."
    }
}

private struct RootStateTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .default))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct RootboxHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(height: 1)
    }
}
