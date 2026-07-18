import Foundation

/// Helpers for reasoning about clock times as minutes.
enum SleepTime {
    /// Minutes since midnight (0–1439).
    static func minutesOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Minutes since 6pm (0–1439), so late-evening and past-midnight bedtimes
    /// sit on a continuous scale (23:00 = 300, 02:00 = 491).
    static func minutesSinceEvening(_ date: Date, calendar: Calendar = .current) -> Int {
        (minutesOfDay(date, calendar: calendar) - 18 * 60 + 1440) % 1440
    }
}

/// A personal, rolling baseline of the sleeper's recent nights, used to judge
/// whether tonight's bedtime and wake time are "usual" for *them* rather than
/// against a fixed reference. Mirrors how Oura/WHOOP compare against your own
/// trailing history once enough nights exist.
struct SleepBaseline {
    /// Median bedtime, in minutes since 6pm. Nil when there isn't enough data.
    let bedtimeMinutes: Int?
    /// Median wake time, in minutes since midnight. Nil when insufficient.
    let wakeMinutes: Int?
    /// Number of prior nights the baseline was computed from.
    let nightCount: Int

    static let empty = SleepBaseline(bedtimeMinutes: nil, wakeMinutes: nil, nightCount: 0)

    /// Minimum nights before we trust the personal baseline (the calibration
    /// window, à la WHOOP). Below this we fall back to fixed reference times.
    static let calibrationThreshold = 7

    var isCalibrated: Bool {
        nightCount >= Self.calibrationThreshold && bedtimeMinutes != nil && wakeMinutes != nil
    }

    init(bedtimeMinutes: Int?, wakeMinutes: Int?, nightCount: Int) {
        self.bedtimeMinutes = bedtimeMinutes
        self.wakeMinutes = wakeMinutes
        self.nightCount = nightCount
    }

    /// Builds a baseline from prior nights using medians (robust to outliers).
    init(sessions: [SleepSession], calendar: Calendar = .current) {
        nightCount = sessions.count
        bedtimeMinutes = Self.median(sessions.map { SleepTime.minutesSinceEvening($0.sleepOnset, calendar: calendar) })
        wakeMinutes = Self.median(sessions.map { SleepTime.minutesOfDay($0.inBedEnd, calendar: calendar) })
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
