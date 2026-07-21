import Foundation

private struct FuzzerRNG: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func int(_ upperBound: Int) -> Int {
        Int(next() % UInt64(upperBound))
    }
}

private struct ViewportState {
    var range: TrendRange
    var start: Date
    var anchor: Date
    var firstDay: Date
    let lastDay: Date
}

private func require(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FUZZ FAILURE: \(message())\n".utf8))
        exit(1)
    }
}

private func run(seed: UInt64, calendar sourceCalendar: Calendar, sequences: Int, steps: Int) {
    let calendar = sourceCalendar
    let lastDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_783_920_000)) // 2026-07-13 UTC week
    let fiveYearsAgo = calendar.date(byAdding: .year, value: -5, to: lastDay)!
    var rng = FuzzerRNG(state: seed == 0 ? 1 : seed)

    for _ in 0..<sequences {
        var state = ViewportState(
            range: TrendRange.allCases[rng.int(TrendRange.allCases.count)],
            start: lastDay,
            anchor: lastDay,
            firstDay: calendar.date(byAdding: .day, value: -364, to: lastDay)!,
            lastDay: lastDay
        )
        state.start = TrendViewportMath.retargetedStart(
            anchorDay: state.anchor,
            range: state.range,
            firstDay: state.firstDay,
            lastDay: state.lastDay,
            calendar: calendar
        )
        state.anchor = TrendViewportMath.trailingDay(for: state.start, range: state.range, calendar: calendar)

        for _ in 0..<steps {
            switch rng.int(5) {
            case 0, 1:
                // A drag/fling can project many screens in either direction.
                let delta = rng.int(900) - 450
                let proposed = calendar.date(byAdding: .day, value: delta, to: state.start)!
                state.start = TrendViewportMath.snappedStart(
                    proposedStart: proposed,
                    range: state.range,
                    firstDay: state.firstDay,
                    lastDay: state.lastDay,
                    calendar: calendar
                )
                state.anchor = TrendViewportMath.trailingDay(for: state.start, range: state.range, calendar: calendar)

            case 2, 3:
                // Rapid W/M/6M switching must retain the inclusive trailing day.
                let oldAnchor = state.anchor
                state.range = TrendRange.allCases[rng.int(TrendRange.allCases.count)]
                state.start = TrendViewportMath.retargetedStart(
                    anchorDay: oldAnchor,
                    range: state.range,
                    firstDay: state.firstDay,
                    lastDay: state.lastDay,
                    calendar: calendar
                )
                state.anchor = TrendViewportMath.trailingDay(for: state.start, range: state.range, calendar: calendar)
                let unclampedStart = TrendViewportMath.startDay(
                    endingAt: oldAnchor,
                    range: state.range,
                    calendar: calendar
                )
                if unclampedStart >= state.firstDay,
                   TrendViewportMath.trailingDay(for: unclampedStart, range: state.range, calendar: calendar) <= state.lastDay {
                    require(state.anchor == oldAnchor, "bucket switch changed anchor")
                }

            default:
                // Simulate older chunks arriving while the user is interacting.
                if state.firstDay > fiveYearsAgo {
                    state.firstDay = max(fiveYearsAgo, calendar.date(byAdding: .day, value: -365, to: state.firstDay)!)
                }
            }

            let latestStart = TrendViewportMath.startDay(
                endingAt: state.lastDay,
                range: state.range,
                calendar: calendar
            )
            require(state.start >= state.firstDay, "start escaped lower data bound")
            require(state.start <= max(state.firstDay, latestStart), "start escaped upper data bound")
            require(calendar.startOfDay(for: state.start) == state.start, "start is not local midnight")
            require(
                TrendViewportMath.startDay(endingAt: state.anchor, range: state.range, calendar: calendar) == state.start,
                "start/anchor round trip failed"
            )
        }
    }
}

@main
private enum TrendStateFuzzer {
    static func main() {
        let zones = ["America/Los_Angeles", "Europe/Berlin", "Asia/Kathmandu", "Pacific/Auckland"]
        for (zoneIndex, zoneName) in zones.enumerated() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zoneName)!
            calendar.firstWeekday = zoneIndex.isMultiple(of: 2) ? 1 : 2
            run(seed: 0x851_000 + UInt64(zoneIndex), calendar: calendar, sequences: 500, steps: 500)
        }

        print("Trend state fuzz passed: 1,000,000 transitions across 4 time zones and 5 years")
    }
}
