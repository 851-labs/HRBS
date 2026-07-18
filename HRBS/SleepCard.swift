import SwiftUI
import Charts

/// Recreates the Apple Health "Time Asleep" card: a headline duration, the
/// in-bed time range, a stage timeline chart, and a per-stage breakdown.
struct SleepCard: View {
    let session: SleepSession
    var age: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "bed.double.fill")
                    .foregroundStyle(SleepStage.deep.color)
                Text("Sleep")
                    .font(.headline)
                    .foregroundStyle(SleepStage.deep.color)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Time Asleep")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(session.timeAsleep.hoursMinutesString)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("\(session.inBedStart, format: .dateTime.hour().minute()) – \(session.inBedEnd, format: .dateTime.hour().minute())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            SleepStagesChart(session: session)
                .frame(height: 150)

            SleepOverview(session: session, age: age)
                .padding(.top, 4)
        }
        .cardStyle()
    }
}

/// A Gantt-style timeline of sleep stages over the night, drawn with Swift
/// Charts to match the Apple Health rendering (Awake on top, Deep on bottom).
struct SleepStagesChart: View {
    let session: SleepSession

    var body: some View {
        Chart(session.segments) { segment in
            BarMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                y: .value("Stage", segment.stage.rawValue)
            )
            .foregroundStyle(segment.stage.color)
            .cornerRadius(3)
        }
        // Charts places the first domain element at the bottom, so reverse the
        // top-to-bottom display order to put Awake on top and Deep on the bottom.
        .chartYScale(domain: SleepStage.displayOrder.reversed().map(\.rawValue))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let name = value.as(String.self), let stage = SleepStage(rawValue: name) {
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(stage.color)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }
}

#Preview {
    SleepCard(session: SampleDataProvider.data(for: Date()).sleep)
        .padding()
        .background(Color.groupedBackground)
}
