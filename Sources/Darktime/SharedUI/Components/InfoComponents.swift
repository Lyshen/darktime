import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DTColor.muted)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(tint.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct InfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DTColor.muted)
                        .frame(width: 132, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11, design: row.1.contains("/") ? .monospaced : .default))
                        .foregroundStyle(DTColor.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                if row.0 != rows.last?.0 {
                    Divider().overlay(DTColor.line)
                }
            }
        }
        .padding(.horizontal, 10)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct AgentRow: View {
    let session: MCPSessionSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor(session.lastToolStatus ?? "started"))
                .frame(width: 30, height: 30)
                .background(statusColor(session.lastToolStatus ?? "started").opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(session.clientName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(session.toolCallCount) calls")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DTColor.muted)
                }
                Text("\(session.transport) / \(session.lastToolName ?? "server_started") / \(session.lastToolStatus ?? "started")")
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .lineLimit(1)
                Text("last seen \(formatRelative(session.lastSeenAt))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
            }
        }
        .padding(11)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct TinyTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct EmptyStateLine: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 28, height: 28)
                .background(DTColor.row)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct SectionEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DTColor.dimmed)
            .tracking(0)
    }
}

struct SignalDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.45), radius: 5)
    }
}

