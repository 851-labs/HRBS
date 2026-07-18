import SwiftUI

/// A 2×2 grid of headline sleep metrics shown above the stage chart:
/// Sleep Duration, Restorative Sleep, Fell Asleep At, and Woke Up At — each with
/// a large value and a color-coded status.
struct SleepMetricsGrid: View {
    let session: SleepSession

    private let columns = [
        GridItem(.flexible(), alignment: .topLeading),
        GridItem(.flexible(), alignment: .topLeading),
    ]

    private var restorative: TimeInterval {
        session.duration(for: .deep) + session.duration(for: .rem)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            MetricTile(
                title: "Sleep Duration",
                value: SleepMetric.durationValue(session.timeAsleep),
                status: SleepMetric.durationStatus(session.timeAsleep)
            )
            MetricTile(
                title: "Restorative Sleep",
                value: SleepMetric.durationValue(restorative),
                status: SleepMetric.restorativeStatus(restorative)
            )
            MetricTile(
                title: "Fell Asleep At",
                value: SleepMetric.timeValue(session.sleepOnset),
                status: SleepMetric.fellAsleepStatus(session.sleepOnset)
            )
            MetricTile(
                title: "Woke Up At",
                value: SleepMetric.timeValue(session.inBedEnd),
                status: SleepMetric.wokeUpStatus(session.inBedEnd)
            )
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: Text
    let status: MetricStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            value

            HStack(spacing: 4) {
                Image(systemName: status.symbol)
                Text(status.label)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(status.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Color-coded assessment shown beneath a metric value.
struct MetricStatus {
    let label: String
    let symbol: String
    let color: Color
}

/// Computes metric values and their heuristic statuses.
///
/// Note: without a personal history to establish a "usual" baseline, the timing
/// statuses compare against fixed reference times (bedtime ~23:00, wake ~07:00)
/// and the duration statuses against general adult guidance. These thresholds
/// are intentionally simple and easy to tune.
enum SleepMetric {
    private static let numberFont = Font.system(size: 30, weight: .bold, design: .rounded)
    private static let unitFont = Font.system(size: 15, weight: .semibold, design: .rounded)

    static func durationValue(_ interval: TimeInterval) -> Text {
        let totalMinutes = Int((interval / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return Text("\(hours)").font(numberFont)
                + Text("h").font(unitFont).foregroundColor(.secondary)
                + Text(" \(minutes)").font(numberFont)
                + Text("m").font(unitFont).foregroundColor(.secondary)
        }
        return Text("\(minutes)").font(numberFont)
            + Text("m").font(unitFont).foregroundColor(.secondary)
    }

    static func timeValue(_ date: Date) -> Text {
        Text(date, format: .dateTime.hour().minute()).font(numberFont)
    }

    // MARK: - Statuses

    static func durationStatus(_ interval: TimeInterval) -> MetricStatus {
        let hours = interval / 3600
        switch hours {
        case ..<5:  return MetricStatus(label: "Very Low", symbol: "chevron.down.circle.fill", color: .red)
        case ..<6:  return MetricStatus(label: "Low", symbol: "chevron.down.circle.fill", color: .orange)
        case ...9:  return MetricStatus(label: "Normal", symbol: "checkmark.circle.fill", color: .green)
        default:    return MetricStatus(label: "High", symbol: "chevron.up.circle.fill", color: .blue)
        }
    }

    static func restorativeStatus(_ interval: TimeInterval) -> MetricStatus {
        let hours = interval / 3600
        switch hours {
        case ..<1.5: return MetricStatus(label: "Low", symbol: "chevron.down.circle.fill", color: .orange)
        case ...3.5: return MetricStatus(label: "Normal", symbol: "checkmark.circle.fill", color: .green)
        default:     return MetricStatus(label: "High", symbol: "chevron.up.circle.fill", color: .blue)
        }
    }

    static func fellAsleepStatus(_ onset: Date) -> MetricStatus {
        // Minutes since 6pm, so late-evening and past-midnight bedtimes compare cleanly.
        let usual = 5 * 60 // 23:00
        let delta = minutesSinceEvening(onset) - usual
        if delta > 30 {
            return MetricStatus(label: "Later Than Usual", symbol: "chevron.up.circle.fill", color: .orange)
        } else if delta < -30 {
            return MetricStatus(label: "Earlier Than Usual", symbol: "chevron.down.circle.fill", color: .teal)
        }
        return MetricStatus(label: "On Schedule", symbol: "checkmark.circle.fill", color: .green)
    }

    static func wokeUpStatus(_ wake: Date) -> MetricStatus {
        let usual = 7 * 60 // 07:00
        let delta = minutesOfDay(wake) - usual
        if delta > 30 {
            return MetricStatus(label: "Later Than Usual", symbol: "chevron.up.circle.fill", color: .green)
        } else if delta < -30 {
            return MetricStatus(label: "Earlier Than Usual", symbol: "chevron.down.circle.fill", color: .orange)
        }
        return MetricStatus(label: "On Schedule", symbol: "checkmark.circle.fill", color: .green)
    }

    private static func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func minutesSinceEvening(_ date: Date) -> Int {
        (minutesOfDay(date) - 18 * 60 + 1440) % 1440
    }
}

#Preview {
    SleepMetricsGrid(session: SampleDataProvider.data(for: Date()).sleep)
        .padding()
        .background(Color.groupedBackground)
}
