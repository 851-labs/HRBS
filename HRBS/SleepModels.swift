import SwiftUI

/// The stages Apple Health uses when visualizing a night of sleep.
enum SleepStage: String, CaseIterable, Identifiable {
    case awake = "Awake"
    case rem = "REM"
    case core = "Core"
    case deep = "Deep"

    var id: String { rawValue }

    /// Colors chosen to mirror the Apple Health sleep visualization.
    var color: Color {
        switch self {
        case .awake: return Color(red: 1.00, green: 0.53, blue: 0.20) // orange
        case .rem:   return Color(red: 0.36, green: 0.79, blue: 0.98) // light blue
        case .core:  return Color(red: 0.20, green: 0.47, blue: 0.96) // blue
        case .deep:  return Color(red: 0.35, green: 0.30, blue: 0.83) // indigo
        }
    }

    /// Top-to-bottom order as rendered by Apple Health (Awake on top, Deep on the bottom).
    static var displayOrder: [SleepStage] { [.awake, .rem, .core, .deep] }
}

/// A single contiguous period spent in one sleep stage.
struct SleepSegment: Identifiable {
    let id = UUID()
    let stage: SleepStage
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A full night of sleep made up of ordered stage segments.
struct SleepSession {
    let segments: [SleepSegment]

    var inBedStart: Date { segments.first?.start ?? Date() }
    var inBedEnd: Date { segments.last?.end ?? Date() }

    /// The moment the sleeper first fell asleep (first non-awake segment).
    var sleepOnset: Date {
        segments.first(where: { $0.stage != .awake })?.start ?? inBedStart
    }

    /// Total time spent asleep, excluding awake periods.
    var timeAsleep: TimeInterval {
        segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
    }

    func duration(for stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }
}

/// A resting heart rate reading captured shortly before falling asleep.
struct HeartRateReading {
    let bpm: Int
    let timestamp: Date
}

/// One night's pre-sleep heart rate, for the historical trend chart.
struct HeartRateTrendPoint: Identifiable {
    /// The night this reading belongs to (the morning you woke up).
    let date: Date
    let bpm: Int

    var id: Date { date }
}

/// Everything shown on the dashboard for a single selected day.
struct DayData {
    let date: Date
    let sleep: SleepSession
    /// The pre-sleep reading may be missing when no heart rate was recorded.
    let heartRate: HeartRateReading?
    /// The sleeper's age, used to age-adjust the optimal sleep-stage ranges.
    let age: Int?
    /// Rolling baseline of recent nights, used to judge "usual" bed/wake times.
    let baseline: SleepBaseline
}

extension TimeInterval {
    /// Formats a duration the way Apple Health does, e.g. "7 hr 30 min".
    var hoursMinutesString: String {
        let totalMinutes = Int((self / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours) hr \(minutes) min" }
        if hours > 0 { return "\(hours) hr" }
        return "\(minutes) min"
    }
}
