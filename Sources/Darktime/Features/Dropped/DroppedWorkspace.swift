import Foundation
import SwiftUI

struct DroppedWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            DroppedHeader(count: model.droppedMatters.count)
            Divider().overlay(DTColor.line.opacity(0.7))

            ScrollView {
                VStack(spacing: 0) {
                    if model.droppedMatters.isEmpty {
                        EmptyStateLine(
                            systemImage: "xmark.circle",
                            title: "Dropped is empty",
                            detail: "Nothing is waiting in the safety net."
                        )
                        .padding(.top, 34)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.droppedMatters.enumerated()), id: \.element.id) { index, matter in
                                DroppedMatterLine(
                                    model: model,
                                    matter: matter,
                                    isLast: index == model.droppedMatters.count - 1
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
        .background(DTColor.workspace)
    }
}

private struct DroppedHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text("Dropped")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
    }

    private var detail: String {
        let countText = count == 1 ? "1 item" : "\(count) items"
        return "\(countText) · deletes after \(MatterRepository.droppedRetentionDays) days"
    }
}

private struct DroppedMatterLine: View {
    @ObservedObject var model: DashboardModel
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
                    DroppedMetaActionLine(
                        text: droppedMeta,
                        showsRestore: isHovered
                    ) {
                        model.restoreDroppedMatter(matter)
                    }
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

    private var droppedMeta: String {
        "\(formatRelative(matter.updatedAt)) · deletes \(deleteDateText)"
    }

    private var deleteDateText: String {
        guard
            let droppedAt = parseISODate(matter.updatedAt),
            let deleteAt = Calendar.current.date(
                byAdding: .day,
                value: MatterRepository.droppedRetentionDays,
                to: droppedAt
            )
        else {
            return "after \(MatterRepository.droppedRetentionDays)d"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: deleteAt)
    }
}

private struct DroppedMetaActionLine: View {
    let text: String
    let showsRestore: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(DTColor.dimmed)
                .lineLimit(1)
                .truncationMode(.tail)

            if showsRestore {
                Text("·")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)

                Button(action: action) {
                    Text("Restore")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(isHovered ? DTColor.text : DTColor.muted)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovered = hovering
                }
            }
        }
    }
}
