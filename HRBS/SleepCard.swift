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

    private let laneThickness: CGFloat = 20
    private let axisHeight: CGFloat = 18
    private let riserWidth: CGFloat = 4

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

                // Connect the two lanes' inner edges (not centers), so the riser
                // tucks under the chunky segments instead of poking out of them.
                let yStart = min(yTop, yBottom) + laneThickness / 2 - 1
                let yEnd = max(yTop, yBottom) - laneThickness / 2 + 1
                guard yEnd > yStart else { continue }

                let rect = CGRect(x: cx - riserWidth / 2, y: yStart, width: riserWidth, height: yEnd - yStart)
                // A steady two-tone gradient (no fade to white) so even tall
                // risers read as a clean line rather than a ghostly streak.
                let gradient = Gradient(colors: [upper.color.opacity(0.55), lower.color.opacity(0.55)])
                context.fill(
                    Path(roundedRect: rect, cornerRadius: riserWidth / 2),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: cx, y: yStart),
                        endPoint: CGPoint(x: cx, y: yEnd)
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

#if DEBUG
extension SleepSession {
    /// A deliberately fragmented night (frequent brief awakenings, direct
    /// stage jumps, a long awake block) that mirrors real HealthKit data far
    /// better than the smooth sample generator — used to stress-test the chart.
    static var previewFragmented: SleepSession {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 18; comps.hour = 2; comps.minute = 11
        let start = Calendar.current.date(from: comps) ?? Date(timeIntervalSince1970: 0)

        var segments: [SleepSegment] = []
        var cursor = start
        func add(_ stage: SleepStage, _ minutes: Double) {
            let end = cursor.addingTimeInterval(minutes * 60)
            segments.append(SleepSegment(stage: stage, start: cursor, end: end))
            cursor = end
        }

        let plan: [(SleepStage, Double)] = [
            (.awake, 4), (.core, 18), (.deep, 22), (.core, 9), (.deep, 15),
            (.core, 7), (.awake, 2), (.core, 12), (.rem, 6), (.core, 10),
            (.deep, 14), (.core, 8), (.awake, 1), (.rem, 5), (.core, 9),
            (.rem, 4), (.core, 6), (.awake, 2), (.core, 16), (.rem, 12),
            (.core, 5), (.awake, 55), (.core, 10), (.deep, 7), (.core, 9),
            (.rem, 16), (.core, 7), (.awake, 2), (.core, 12), (.rem, 9),
            (.core, 6), (.awake, 3), (.core, 8), (.rem, 5), (.awake, 4),
        ]
        for (stage, minutes) in plan { add(stage, minutes) }
        return SleepSession(segments: segments)
    }
}
#endif

#Preview {
    SleepCard(session: .previewFragmented, age: 30)
        .padding()
        .background(Color.groupedBackground)
}
