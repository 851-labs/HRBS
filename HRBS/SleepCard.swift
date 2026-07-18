import SwiftUI

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

/// The sleep-stage timeline, drawn as a connected ribbon to match Apple Health:
/// each stage is a rounded bar in its own lane (Awake on top, Deep on the
/// bottom) and consecutive stages are joined by a thin gradient "riser". Swift
/// Charts has no mark for this, so it's a custom Canvas.
struct SleepStagesChart: View {
    let session: SleepSession

    /// Lanes from top to bottom, matching Apple Health.
    private let lanes: [SleepStage] = [.awake, .rem, .core, .deep]

    private let laneThickness: CGFloat = 16
    private let axisHeight: CGFloat = 18
    private let riserWidth: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let segments = session.segments
            guard let first = segments.first, let last = segments.last else { return }

            let start = first.start
            let end = last.end
            let span = max(end.timeIntervalSince(start), 1)

            let plotHeight = size.height - axisHeight
            let usable = max(plotHeight - laneThickness, 1)
            let laneGap = usable / CGFloat(max(lanes.count - 1, 1))

            func laneIndex(_ stage: SleepStage) -> Int { lanes.firstIndex(of: stage) ?? 0 }
            func centerY(_ stage: SleepStage) -> CGFloat { laneThickness / 2 + CGFloat(laneIndex(stage)) * laneGap }
            func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(start) / span) * size.width }

            drawTimeAxis(context, size: size, start: start, end: end, plotHeight: plotHeight, x: x)

            // Risers first, so the solid segments sit on top of them.
            for i in 0..<(segments.count - 1) {
                let a = segments[i], b = segments[i + 1]
                guard laneIndex(a.stage) != laneIndex(b.stage) else { continue }

                let upper = centerY(a.stage) < centerY(b.stage) ? a.stage : b.stage
                let lower = centerY(a.stage) < centerY(b.stage) ? b.stage : a.stage
                let yTop = centerY(upper)
                let yBottom = centerY(lower)
                let cx = x(b.start)

                let rect = CGRect(x: cx - riserWidth / 2, y: yTop, width: riserWidth, height: yBottom - yTop)
                let gradient = Gradient(stops: [
                    .init(color: upper.color.opacity(0.85), location: 0.0),
                    .init(color: upper.color.opacity(0.22), location: 0.32),
                    .init(color: lower.color.opacity(0.22), location: 0.68),
                    .init(color: lower.color.opacity(0.85), location: 1.0),
                ])
                context.fill(
                    Path(roundedRect: rect, cornerRadius: riserWidth / 2),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: cx, y: yTop),
                        endPoint: CGPoint(x: cx, y: yBottom)
                    )
                )
            }

            // Solid stage segments.
            for segment in segments {
                let x0 = x(segment.start)
                let width = max(x(segment.end) - x0, riserWidth)
                let cy = centerY(segment.stage)
                let rect = CGRect(x: x0, y: cy - laneThickness / 2, width: width, height: laneThickness)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 4, style: .continuous),
                    with: .color(segment.stage.color)
                )
            }
        }
    }

    private func drawTimeAxis(
        _ context: GraphicsContext,
        size: CGSize,
        start: Date,
        end: Date,
        plotHeight: CGFloat,
        x: (Date) -> CGFloat
    ) {
        let calendar = Calendar.current

        // Interior gridlines every two hours, aligned to the clock.
        var ticks: [Date] = []
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: start)
        if let hour = comps.hour {
            comps.hour = hour - (hour % 2) + 2
            comps.minute = 0
            comps.second = 0
            if var tick = calendar.date(from: comps) {
                while tick < end {
                    ticks.append(tick)
                    guard let next = calendar.date(byAdding: .hour, value: 2, to: tick) else { break }
                    tick = next
                }
            }
        }

        for tick in ticks {
            let gx = x(tick)
            var line = Path()
            line.move(to: CGPoint(x: gx, y: 0))
            line.addLine(to: CGPoint(x: gx, y: plotHeight))
            context.stroke(
                line,
                with: .color(.gray.opacity(0.18)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 3])
            )
        }

        // Only label the interior hour ticks; the full bed/wake range is already
        // shown in the card header, which avoids labels colliding at the edges.
        let labelY = plotHeight + axisHeight / 2
        for tick in ticks {
            let text = Text(tick.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
            context.draw(text, at: CGPoint(x: x(tick), y: labelY), anchor: .center)
        }
    }
}

#Preview {
    SleepCard(session: SampleDataProvider.data(for: Date()).sleep)
        .padding()
        .background(Color.groupedBackground)
}
