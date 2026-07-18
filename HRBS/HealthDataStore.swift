#if os(iOS)
import Foundation
import HealthKit

/// Reads sleep and pre-sleep heart rate data from HealthKit using Swift
/// concurrency. This is the real-data replacement for `SampleDataProvider`.
@MainActor
final class HealthDataStore {
    private let store = HKHealthStore()

    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private var beatsPerMinute: HKUnit { HKUnit.count().unitDivided(by: .minute()) }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Presents the HealthKit permission sheet for the data we read.
    func requestAuthorization() async {
        guard isAvailable else { return }
        let readTypes: Set<HKObjectType> = [
            sleepType,
            heartRateType,
            HKCharacteristicType(.dateOfBirth),
        ]
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// The user's current age from their HealthKit date of birth, if available.
    func currentAge(calendar: Calendar = .current) -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = calendar.date(from: components) else {
            return nil
        }
        return calendar.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// Builds a day's dashboard data from HealthKit, or `nil` when no sleep
    /// was recorded for the night ending on the given day.
    func dayData(for date: Date, calendar: Calendar = .current) async -> DayData? {
        guard isAvailable, let session = await sleepSession(for: date, calendar: calendar) else {
            return nil
        }
        let reading = await heartRate(before: session.sleepOnset)
        let priorNights = await recentSessions(before: date, calendar: calendar)
        return DayData(
            date: date,
            sleep: session,
            heartRate: reading,
            age: currentAge(calendar: calendar),
            baseline: SleepBaseline(sessions: priorNights, calendar: calendar)
        )
    }

    /// The pre-sleep heart rate for each of the last `days` nights, oldest first.
    func heartRateTrend(days: Int, calendar: Calendar = .current) async -> [HeartRateTrendPoint] {
        guard isAvailable else { return [] }
        let today = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let start = windowStart.addingTimeInterval(-12 * 3600)
        let end = min(today.addingTimeInterval(12 * 3600), Date())

        let segments = await stageSegments(from: start, to: end)

        var byNight: [Date: [SleepSegment]] = [:]
        for segment in segments {
            byNight[nightDate(for: segment.start, calendar: calendar), default: []].append(segment)
        }

        let nights = byNight.map { night, segs in
            (date: night, session: SleepSession(segments: segs.sorted { $0.start < $1.start }))
        }

        // Query each night's pre-sleep heart rate concurrently.
        var points: [HeartRateTrendPoint] = []
        await withTaskGroup(of: HeartRateTrendPoint?.self) { group in
            for night in nights {
                group.addTask {
                    guard let reading = await self.heartRate(before: night.session.sleepOnset) else { return nil }
                    return HeartRateTrendPoint(date: night.date, bpm: reading.bpm)
                }
            }
            for await point in group where point != nil {
                points.append(point!)
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    // MARK: - Sleep

    private func sleepSession(for date: Date, calendar: Calendar) async -> SleepSession? {
        // Apple Health attributes a night to the day you wake up, so query a
        // 24-hour window centered on the selected day's midnight.
        let midnight = calendar.startOfDay(for: date)
        let start = midnight.addingTimeInterval(-12 * 3600)
        let end = min(midnight.addingTimeInterval(12 * 3600), Date())
        guard end > start else { return nil }

        let segments = await stageSegments(from: start, to: end)
        return segments.isEmpty ? nil : SleepSession(segments: segments)
    }

    /// The prior nights (up to `window`) before the selected day, used to build
    /// a rolling personal baseline. One range query, grouped into nights by the
    /// day each night ends on (the same noon-to-noon rule as `sleepSession`).
    private func recentSessions(before date: Date, window: Int = 28, calendar: Calendar = .current) async -> [SleepSession] {
        let selectedMidnight = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -(window + 1), to: selectedMidnight) else {
            return []
        }
        // Prior nights only — stop at the selected day's midnight.
        let segments = await stageSegments(from: start, to: selectedMidnight)

        var byNight: [Date: [SleepSegment]] = [:]
        for segment in segments {
            let night = nightDate(for: segment.start, calendar: calendar)
            guard night < selectedMidnight else { continue }
            byNight[night, default: []].append(segment)
        }

        return byNight.values
            .map { SleepSession(segments: $0.sorted { $0.start < $1.start }) }
            .filter { !$0.segments.isEmpty }
    }

    /// The date a sleep period is attributed to (the morning you wake up): a
    /// segment starting after noon belongs to the next calendar day's night.
    private func nightDate(for start: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: start)
        let hour = calendar.component(.hour, from: start)
        return hour >= 12 ? (calendar.date(byAdding: .day, value: 1, to: day) ?? day) : day
    }

    /// Reads stage-level sleep segments in a time range (excludes the whole-night
    /// "in bed" envelope). Shared by the day view and the baseline query.
    private func stageSegments(from start: Date, to end: Date) async -> [SleepSegment] {
        guard end > start else { return [] }

        let timePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let stagePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: stageValues.map {
            HKQuery.predicateForCategorySamples(with: .equalTo, value: $0.rawValue)
        })
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, stagePredicate])

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: combined)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )

        guard let samples = try? await descriptor.result(for: store) else { return [] }

        return samples.compactMap { sample -> SleepSegment? in
            guard let stage = stage(for: sample.value) else { return nil }
            return SleepSegment(stage: stage, start: sample.startDate, end: sample.endDate)
        }
    }

    /// The stage-level sleep values we care about (the whole-night "in bed"
    /// envelope is intentionally excluded from the stage timeline).
    private var stageValues: [HKCategoryValueSleepAnalysis] {
        [.awake, .asleepREM, .asleepCore, .asleepDeep, .asleepUnspecified]
    }

    private func stage(for value: Int) -> SleepStage? {
        if value == HKCategoryValueSleepAnalysis.awake.rawValue { return .awake }
        if value == HKCategoryValueSleepAnalysis.asleepREM.rawValue { return .rem }
        if value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue { return .deep }
        if value == HKCategoryValueSleepAnalysis.asleepCore.rawValue { return .core }
        // Any other asleep value (unspecified, or legacy "asleep") counts as core.
        if HKCategoryValueSleepAnalysis.allAsleepValues.contains(where: { $0.rawValue == value }) {
            return .core
        }
        return nil
    }

    // MARK: - Heart rate

    private func heartRate(before onset: Date) async -> HeartRateReading? {
        let windowStart = onset.addingTimeInterval(-30 * 60)
        let timePredicate = HKQuery.predicateForSamples(withStart: windowStart, end: onset, options: [])

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heartRateType, predicate: timePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )

        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else {
            return nil
        }

        // Pick the reading closest to five minutes before sleep onset.
        let target = onset.addingTimeInterval(-5 * 60)
        guard let best = samples.min(by: {
            abs($0.startDate.timeIntervalSince(target)) < abs($1.startDate.timeIntervalSince(target))
        }) else {
            return nil
        }

        let bpm = Int(best.quantity.doubleValue(for: beatsPerMinute).rounded())
        return HeartRateReading(bpm: bpm, timestamp: best.startDate)
    }
}
#endif
