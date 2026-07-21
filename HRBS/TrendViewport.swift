import Foundation

/// The bucket size for the trends chart, mirroring Apple Health's W / M / 6M.
enum TrendRange: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case sixMonths = "6M"

    var id: String { rawValue }

    /// Number of days visible at once.
    var visibleDays: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 182
        }
    }

    var visibleSeconds: TimeInterval { Double(visibleDays) * 86_400 }

    /// Aggregates daily readings into weekly averages for the 6-month view.
    var aggregatesWeekly: Bool { self == .sixMonths }
}

/// Pure calendar math shared by the chart and the deterministic fuzz test.
/// Keeping it independent from SwiftUI makes state transitions inexpensive to
/// exercise hundreds of thousands of times.
enum TrendViewportMath {
    static func trailingDay(for start: Date, range: TrendRange, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: range.visibleDays - 1, to: calendar.startOfDay(for: start))
            ?? calendar.startOfDay(for: start)
    }

    static func startDay(endingAt end: Date, range: TrendRange, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -(range.visibleDays - 1), to: calendar.startOfDay(for: end))
            ?? calendar.startOfDay(for: end)
    }

    static func clampedStart(
        _ proposed: Date,
        range: TrendRange,
        firstDay: Date,
        lastDay: Date,
        calendar: Calendar
    ) -> Date {
        let first = calendar.startOfDay(for: firstDay)
        let latest = startDay(endingAt: lastDay, range: range, calendar: calendar)
        return min(max(calendar.startOfDay(for: proposed), first), max(first, latest))
    }

    static func retargetedStart(
        anchorDay: Date,
        range: TrendRange,
        firstDay: Date,
        lastDay: Date,
        calendar: Calendar
    ) -> Date {
        clampedStart(
            startDay(endingAt: anchorDay, range: range, calendar: calendar),
            range: range,
            firstDay: firstDay,
            lastDay: lastDay,
            calendar: calendar
        )
    }

    static func snappedStart(
        proposedStart: Date,
        range: TrendRange,
        firstDay: Date,
        lastDay: Date,
        calendar: Calendar
    ) -> Date {
        let proposed = calendar.startOfDay(for: proposedStart)
        let interval: DateInterval?
        switch range {
        case .week, .month:
            interval = calendar.dateInterval(of: .weekOfYear, for: proposed)
        case .sixMonths:
            interval = calendar.dateInterval(of: .month, for: proposed)
        }
        guard let interval else {
            return clampedStart(
                proposed,
                range: range,
                firstDay: firstDay,
                lastDay: lastDay,
                calendar: calendar
            )
        }

        let before = abs(proposed.timeIntervalSince(interval.start))
        let after = abs(interval.end.timeIntervalSince(proposed))
        let boundary = before <= after ? interval.start : interval.end
        return clampedStart(
            boundary,
            range: range,
            firstDay: firstDay,
            lastDay: lastDay,
            calendar: calendar
        )
    }
}
