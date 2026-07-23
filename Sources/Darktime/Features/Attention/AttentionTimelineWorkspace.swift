import Foundation
import SwiftUI

enum AttentionTimelineRange: String, CaseIterable, Identifiable {
    case fortyEightHours = "48H"
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"
    case oneYear = "1Y"

    var id: String { rawValue }

    var cellWidth: CGFloat {
        switch self {
        case .fortyEightHours: return 5
        case .sevenDays: return 26
        case .thirtyDays: return 7
        case .ninetyDays: return 17
        case .oneYear: return 7
        }
    }

    var cellHeight: CGFloat {
        switch self {
        case .sevenDays: return 17
        default: return 16
        }
    }

    var cellSpacing: CGFloat {
        switch self {
        case .sevenDays: return 5
        case .ninetyDays: return 3
        default: return 2
        }
    }

    func fittedCellWidth(in width: CGFloat) -> CGFloat {
        let count = CGFloat(bucketCount)
        let spacingWidth = max(0, count - 1) * cellSpacing
        return max(1, (width - spacingWidth) / count)
    }

    var bucketCount: Int {
        switch self {
        case .fortyEightHours: return 48
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 13
        case .oneYear: return 36
        }
    }

    fileprivate func buckets(now: Date = Date(), calendar: Calendar = .current) -> [AttentionTimelineBucket] {
        switch self {
        case .fortyEightHours:
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let first = calendar.date(byAdding: .hour, value: -47, to: currentHour) ?? currentHour
            return (0..<48).compactMap { offset in
                guard
                    let start = calendar.date(byAdding: .hour, value: offset, to: first),
                    let end = calendar.date(byAdding: .hour, value: 1, to: start)
                else {
                    return nil
                }
                return AttentionTimelineBucket(start: start, end: end, unit: .hour)
            }
        case .sevenDays:
            return dayBuckets(count: 7, now: now, calendar: calendar)
        case .thirtyDays:
            return dayBuckets(count: 30, now: now, calendar: calendar)
        case .ninetyDays:
            let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            let first = calendar.date(byAdding: .weekOfYear, value: -12, to: currentWeek) ?? currentWeek
            return (0..<13).compactMap { offset in
                guard
                    let start = calendar.date(byAdding: .weekOfYear, value: offset, to: first),
                    let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
                else {
                    return nil
                }
                return AttentionTimelineBucket(start: start, end: end, unit: .week)
            }
        case .oneYear:
            return tenDayBuckets(now: now, calendar: calendar)
        }
    }

    func heatLevel(for count: Int) -> Int {
        guard count > 0 else {
            return 0
        }

        switch self {
        case .fortyEightHours:
            if count >= 3 { return 3 }
            return count == 2 ? 2 : 1
        case .sevenDays:
            if count >= 4 { return 3 }
            return count >= 2 ? 2 : 1
        case .thirtyDays, .ninetyDays, .oneYear:
            if count >= 5 { return 3 }
            return count >= 2 ? 2 : 1
        }
    }

    private func dayBuckets(count: Int, now: Date, calendar: Calendar) -> [AttentionTimelineBucket] {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        return (0..<count).compactMap { offset in
            guard
                let start = calendar.date(byAdding: .day, value: offset, to: first),
                let end = calendar.date(byAdding: .day, value: 1, to: start)
            else {
                return nil
            }
            return AttentionTimelineBucket(start: start, end: end, unit: .day)
        }
    }

    private func tenDayBuckets(now: Date, calendar: Calendar) -> [AttentionTimelineBucket] {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return []
        }

        var period = AttentionTimelineTenDayPeriod(
            year: year,
            month: month,
            segment: day <= 10 ? 0 : (day <= 20 ? 1 : 2)
        )
        var periods: [AttentionTimelineTenDayPeriod] = []
        for _ in 0..<36 {
            periods.append(period)
            period = period.previous()
        }

        return periods.reversed().compactMap { period in
            guard let start = calendar.date(from: DateComponents(year: period.year, month: period.month, day: period.startDay)) else {
                return nil
            }

            let end: Date?
            if period.segment < 2 {
                end = calendar.date(from: DateComponents(year: period.year, month: period.month, day: period.endDay))
            } else {
                let monthStart = calendar.date(from: DateComponents(year: period.year, month: period.month, day: 1)) ?? start
                end = calendar.date(byAdding: .month, value: 1, to: monthStart)
            }

            guard let end else {
                return nil
            }
            return AttentionTimelineBucket(start: start, end: end, unit: .tenDay)
        }
    }
}

private enum AttentionTimelineLayout {
    static let contentWidth: CGFloat = 820
    static let labelWidth: CGFloat = 168
    static let horizontalSpacing: CGFloat = 14
    static let summaryWidth: CGFloat = 74
    static let axisLabelWidth: CGFloat = 128

    static var stripWidth: CGFloat {
        contentWidth - labelWidth - summaryWidth - horizontalSpacing * 2
    }

    static var stripLeading: CGFloat {
        labelWidth + horizontalSpacing
    }
}

struct AttentionTimelineRangePicker: View {
    @Binding var selection: AttentionTimelineRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AttentionTimelineRange.allCases) { range in
                Button {
                    selection = range
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(selection == range ? DTColor.text : DTColor.muted)
                        .padding(.horizontal, 6)
                        .frame(height: 23)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selection == range ? Color.white : Color.clear)
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

struct AttentionTimelineWorkspace: View {
    let repos: [LocalRepoSnapshot]
    let actions: [ActionSnapshot]
    let range: AttentionTimelineRange

    var body: some View {
        let buckets = range.buckets()
        let rows = timelineRows(for: buckets)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if rows.isEmpty {
                    EmptyStateLine(
                        systemImage: "waveform.path.ecg",
                        title: "No project actions",
                        detail: "Add a local repo to see real movement over time."
                    )
                } else {
                    AttentionTimelineAxis(range: range, buckets: buckets)
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.repo.project.id) { row in
                            AttentionTimelineRow(row: row, range: range, buckets: buckets)
                            if row.repo.project.id != rows.last?.repo.project.id {
                                AttentionTimelineHairline()
                            }
                        }
                    }
                }
            }
            .frame(width: AttentionTimelineLayout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 42)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
    }

    private func timelineRows(for buckets: [AttentionTimelineBucket]) -> [AttentionTimelineRowData] {
        let commitActions = actions.filter { $0.source == "local_git" && $0.kind == "commit" }
        let actionsByProject = Dictionary(grouping: commitActions, by: \.projectId)

        return repos
            .map { repo in
                let dates = (actionsByProject[repo.project.id] ?? []).compactMap { parseISODate($0.happenedAt) }
                let counts = buckets.map { bucket in
                    dates.filter { $0 >= bucket.start && $0 < bucket.end }.count
                }
                return AttentionTimelineRowData(repo: repo, counts: counts, total: counts.reduce(0, +))
            }
            .sorted { left, right in
                if left.total != right.total {
                    return left.total > right.total
                }
                return left.repo.project.title.localizedCaseInsensitiveCompare(right.repo.project.title) == .orderedAscending
            }
    }
}

private struct AttentionTimelineTenDayPeriod {
    let year: Int
    let month: Int
    let segment: Int

    var startDay: Int {
        switch segment {
        case 0: return 1
        case 1: return 11
        default: return 21
        }
    }

    var endDay: Int {
        switch segment {
        case 0: return 11
        case 1: return 21
        default: return 1
        }
    }

    func previous() -> AttentionTimelineTenDayPeriod {
        if segment > 0 {
            return AttentionTimelineTenDayPeriod(year: year, month: month, segment: segment - 1)
        }
        if month > 1 {
            return AttentionTimelineTenDayPeriod(year: year, month: month - 1, segment: 2)
        }
        return AttentionTimelineTenDayPeriod(year: year - 1, month: 12, segment: 2)
    }
}

private enum AttentionTimelineBucketUnit {
    case hour
    case day
    case week
    case tenDay
}

private struct AttentionTimelineBucket: Identifiable {
    let start: Date
    let end: Date
    let unit: AttentionTimelineBucketUnit

    var id: TimeInterval {
        start.timeIntervalSince1970
    }
}

private struct AttentionTimelineRowData {
    let repo: LocalRepoSnapshot
    let counts: [Int]
    let total: Int
}

private struct AttentionTimelineAxis: View {
    let range: AttentionTimelineRange
    let buckets: [AttentionTimelineBucket]

    var body: some View {
        ZStack(alignment: .leading) {
            Text(axisStart)
                .frame(width: AttentionTimelineLayout.axisLabelWidth, alignment: .leading)
                .offset(x: AttentionTimelineLayout.stripLeading)

            Text(axisEnd)
                .frame(width: AttentionTimelineLayout.axisLabelWidth, alignment: .trailing)
                .offset(x: AttentionTimelineLayout.stripLeading + AttentionTimelineLayout.stripWidth - AttentionTimelineLayout.axisLabelWidth)
        }
        .font(.system(size: 10, weight: .regular, design: .default))
        .foregroundStyle(DTColor.dimmed)
        .lineLimit(1)
        .frame(width: AttentionTimelineLayout.contentWidth, height: 12, alignment: .leading)
    }

    private var axisStart: String {
        guard let start = buckets.first?.start else {
            return ""
        }
        return formatTimelineAxisDate(start, range: range)
    }

    private var axisEnd: String {
        guard let end = buckets.last?.end else {
            return ""
        }
        return formatTimelineAxisDate(Date(timeInterval: -1, since: end), range: range)
    }
}

private struct AttentionTimelineRow: View {
    let row: AttentionTimelineRowData
    let range: AttentionTimelineRange
    let buckets: [AttentionTimelineBucket]

    var body: some View {
        HStack(alignment: .center, spacing: AttentionTimelineLayout.horizontalSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.repo.project.title)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(DTColor.text)
                    .lineLimit(1)

                if let intentionText {
                    Text(intentionText)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.text.opacity(0.48))
                        .lineLimit(1)
                } else {
                    Text(row.repo.repoName)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.dimmed)
                        .lineLimit(1)
                }
            }
            .frame(width: AttentionTimelineLayout.labelWidth, alignment: .leading)

            AttentionTimelineStrip(range: range, buckets: buckets, counts: row.counts)
                .frame(width: AttentionTimelineLayout.stripWidth, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(row.total)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(row.total > 0 ? DTColor.text.opacity(0.76) : DTColor.dimmed)
                Text(lastActiveText)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }
            .frame(width: AttentionTimelineLayout.summaryWidth, alignment: .trailing)
        }
        .frame(width: AttentionTimelineLayout.contentWidth, alignment: .leading)
        .padding(.vertical, 13)
    }

    private var intentionText: String? {
        guard let intention = row.repo.project.intention?.trimmingCharacters(in: .whitespacesAndNewlines), !intention.isEmpty else {
            return nil
        }
        return intention
    }

    private var lastActiveText: String {
        guard
            let lastCommitAt = row.repo.lastCommitAt,
            let date = parseISODate(lastCommitAt)
        else {
            return "no output"
        }
        return "last \(formatTimelineRelative(date))"
    }
}

private struct AttentionTimelineStrip: View {
    let range: AttentionTimelineRange
    let buckets: [AttentionTimelineBucket]
    let counts: [Int]

    var body: some View {
        HStack(alignment: .center, spacing: range.cellSpacing) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                let count = counts.indices.contains(index) ? counts[index] : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(heatColor(for: count))
                    .frame(width: range.fittedCellWidth(in: AttentionTimelineLayout.stripWidth), height: range.cellHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.black.opacity(count > 0 ? 0.03 : 0.045), lineWidth: 1)
                    )
                    .help(formatTimelineBucketHelp(bucket, count: count))
            }
        }
    }

    private func heatColor(for count: Int) -> Color {
        switch range.heatLevel(for: count) {
        case 1:
            return DTColor.green.opacity(0.18)
        case 2:
            return DTColor.green.opacity(0.34)
        case 3:
            return DTColor.green.opacity(0.58)
        default:
            return Color.black.opacity(0.045)
        }
    }
}

private struct AttentionTimelineHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.055))
            .frame(width: AttentionTimelineLayout.contentWidth)
            .frame(height: 1)
    }
}

private func formatTimelineRelative(_ date: Date) -> String {
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

private func formatTimelineAxisDate(_ date: Date, range: AttentionTimelineRange) -> String {
    let formatter = DateFormatter()
    switch range {
    case .fortyEightHours:
        formatter.dateFormat = "MMM d HH:00"
    case .oneYear:
        formatter.dateFormat = "MMM yyyy"
    default:
        formatter.dateFormat = "MMM d"
    }
    return formatter.string(from: date)
}

private func formatTimelineBucketHelp(_ bucket: AttentionTimelineBucket, count: Int) -> String {
    let noun = count == 1 ? "output" : "outputs"
    return "\(formatTimelineBucketRange(bucket)) · \(count) \(noun)"
}

private func formatTimelineBucketRange(_ bucket: AttentionTimelineBucket) -> String {
    let end = Date(timeInterval: -1, since: bucket.end)
    switch bucket.unit {
    case .hour:
        return "\(formatTimelineHour(bucket.start))-\(formatTimelineHour(bucket.end))"
    case .day:
        return formatTimelineMonthDay(bucket.start)
    case .week, .tenDay:
        return "\(formatTimelineMonthDay(bucket.start))-\(formatTimelineMonthDay(end))"
    }
}

private func formatTimelineHour(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:00"
    return formatter.string(from: date)
}

private func formatTimelineMonthDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}
