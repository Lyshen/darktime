import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

struct SourceConnectionRow: View {
    let name: String
    let detail: String
    let status: String
    let statusColor: Color
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(statusColor)
                .background(statusColor.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    SignalDot(color: statusColor)
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CalendarMiniRow: View {
    let calendar: CalendarSnapshot
    let isPreferred: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Circle()
                .fill(Color(hex: calendar.color, fallback: DTColor.cyan))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(calendar.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if isPreferred {
                        Image(systemName: "scope")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DTColor.green)
                    }
                }
                Text("\(calendar.sourceTitle) / \(calendar.sourceType)")
                    .font(.system(size: 11))
                    .foregroundStyle(calendar.sourceType == "local" ? DTColor.amber : DTColor.muted)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: calendar.allowsContentModifications ? "pencil.circle.fill" : "lock.circle.fill")
                .foregroundStyle(calendar.allowsContentModifications ? DTColor.green : DTColor.dimmed)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct PlannedSourceRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock")
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("planned")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DTColor.dimmed)
        }
        .padding(.vertical, 5)
    }
}


