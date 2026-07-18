import Foundation

/// A small deterministic PRNG (xorshift64) so a given day always produces the
/// same sample data. Swapping this out for a HealthKit-backed provider later
/// only requires replacing `SampleDataProvider`.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Generates realistic-looking sleep and pre-sleep heart rate data for a day.
/// The night is treated as ending on the selected morning, matching how Apple
/// Health attributes a night's sleep to the day you wake up.
enum SampleDataProvider {
    static func data(for date: Date, calendar: Calendar = .current) -> DayData {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let seed = UInt64((comps.year ?? 2024) * 10_000
                          + (comps.month ?? 1) * 100
                          + (comps.day ?? 1))
        var rng = SeededGenerator(seed: seed)

        func rand(_ upperBound: UInt64) -> Int { Int(rng.next() % upperBound) }

        let midnight = calendar.startOfDay(for: date)

        // Wake between 6:15 and 7:45; total time in bed between 7h00 and 8h40.
        let wakeMinutes = 6 * 60 + 15 + rand(90)
        let inBedMinutes = 7 * 60 + rand(101)
        let bedtime = midnight.addingTimeInterval(TimeInterval((wakeMinutes - inBedMinutes) * 60))
        let wake = bedtime.addingTimeInterval(TimeInterval(inBedMinutes * 60))

        var segments: [SleepSegment] = []
        var cursor = bedtime

        func append(_ stage: SleepStage, minutes: Int) {
            guard cursor < wake else { return }
            let end = min(wake, cursor.addingTimeInterval(TimeInterval(minutes * 60)))
            guard end > cursor else { return }
            segments.append(SleepSegment(stage: stage, start: cursor, end: end))
            cursor = end
        }

        // Settling in before falling asleep.
        append(.awake, minutes: 3 + rand(6))

        // Sleep cycles: deep sleep dominates early, REM lengthens toward morning.
        var cycle = 0
        while cursor < wake {
            append(.core, minutes: 18 + rand(22))
            append(.deep, minutes: (cycle < 2 ? 20 : 8) + rand(15))
            append(.core, minutes: 10 + rand(15))
            if rand(5) == 0 {
                append(.awake, minutes: 1 + rand(4))
            }
            append(.rem, minutes: (cycle < 1 ? 8 : 14) + rand(16))
            cycle += 1
        }

        let session = SleepSession(segments: segments)

        // Resting heart rate captured five minutes before sleep onset.
        let bpm = 52 + rand(14)
        let hrTimestamp = session.sleepOnset.addingTimeInterval(-5 * 60)
        let reading = HeartRateReading(bpm: bpm, timestamp: hrTimestamp)

        return DayData(date: date, sleep: session, heartRate: reading, age: 30, baseline: .empty)
    }

    /// Pre-sleep heart rate for each night in `fromDay...toDay`, oldest first.
    /// Simulated history only goes back ~400 days so the "load more" path can
    /// reach an end.
    static func heartRateTrend(from fromDay: Date, to toDay: Date, calendar: Calendar = .current) -> [HeartRateTrendPoint] {
        let today = calendar.startOfDay(for: Date())
        let floor = calendar.date(byAdding: .day, value: -400, to: today) ?? today

        var result: [HeartRateTrendPoint] = []
        var day = fromDay
        while day <= toDay {
            if day >= floor, day <= today, let bpm = data(for: day, calendar: calendar).heartRate?.bpm {
                result.append(HeartRateTrendPoint(date: day, bpm: bpm))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
