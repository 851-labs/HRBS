import SwiftUI

/// Recreates the Apple Health "Time Asleep" card: a headline duration, the
/// in-bed time range, a stage timeline chart, and a per-stage breakdown.
struct SleepCard: View {
    let session: SleepSession
    var age: Int? = nil
    var baseline: SleepBaseline = .empty

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

            SleepMetricsGrid(session: session, baseline: baseline)

            SleepStagesChart(session: session)
                .frame(height: 150)

            SleepOverview(session: session, age: age)
                .padding(.top, 4)
        }
        .cardStyle()
    }
}

/// The sleep-stage timeline. The ribbon itself is rendered by the vendored
/// SleepChartKit `SleepTimelineGraph` (see ThirdParty/SleepChartKit); we wrap it
/// with our own hour-based dotted axis and feed it our app's stage colors.
struct SleepStagesChart: View {
    let session: SleepSession

    private let axisHeight: CGFloat = 18

    private var samples: [SleepSample] {
        session.segments.map {
            SleepSample(stage: $0.stage.chartStage, startDate: $0.start, endDate: $0.end)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let plotHeight = geo.size.height - axisHeight
            ZStack(alignment: .top) {
                // Our dotted hour gridlines + labels behind the ribbon.
                Canvas { context, size in
                    drawTimeAxis(context, size: size, plotHeight: plotHeight)
                }
                // The vendored SleepChartKit ribbon, tinted with our colors.
                SleepTimelineGraph(samples: samples, colorProvider: HRBSSleepColorProvider())
                    .frame(height: plotHeight)
            }
        }
    }

    private func drawTimeAxis(_ context: GraphicsContext, size: CGSize, plotHeight: CGFloat) {
        guard let start = session.segments.first?.start,
              let end = session.segments.last?.end else { return }
        let span = max(end.timeIntervalSince(start), 1)
        func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(start) / span) * size.width }

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

/// Bridges the vendored `SleepStageColorProvider` to the app's own stage colors.
private struct HRBSSleepColorProvider: SleepStageColorProvider {
    func color(for stage: SleepChartStage) -> Color {
        switch stage {
        case .awake: return SleepStage.awake.color
        case .asleepREM: return SleepStage.rem.color
        case .asleepCore: return SleepStage.core.color
        case .asleepDeep: return SleepStage.deep.color
        case .asleepUnspecified: return SleepStage.core.color
        case .inBed: return .gray
        }
    }
}

private extension SleepStage {
    /// Maps our stage to the vendored SleepChartKit stage.
    var chartStage: SleepChartStage {
        switch self {
        case .awake: return .awake
        case .rem: return .asleepREM
        case .core: return .asleepCore
        case .deep: return .asleepDeep
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
