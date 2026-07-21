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
                .frame(height: 209)
                .padding(.top, 10)

            SleepOverview(session: session, age: age)
                .padding(.top, 4)
        }
        .cardStyle()
    }
}

/// Apple Health-style sleep-stage timeline with an hourly dotted grid, exact
/// bed/wake endpoints, and a custom gradient ribbon renderer.
struct SleepStagesChart: View {
    let session: SleepSession

    private let axisHeight: CGFloat = 22

    private var samples: [SleepSample] {
        session.segments.map {
            SleepSample(stage: $0.stage.chartStage, startDate: $0.start, endDate: $0.end)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let plotHeight = geo.size.height - axisHeight
            ZStack(alignment: .top) {
                Canvas { context, size in
                    drawTimeAxis(context, size: size, plotHeight: plotHeight)
                }
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

        // Apple uses an hourly dotted grid but labels only even hours.
        var ticks: [Date] = []
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: start)
        comps.minute = 0
        comps.second = 0
        if let rounded = calendar.date(from: comps),
           var tick = calendar.date(byAdding: .hour, value: 1, to: rounded) {
            while tick < end {
                ticks.append(tick)
                guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { break }
                tick = next
            }
        }

        for tick in ticks {
            let gx = x(tick)
            var line = Path()
            line.move(to: CGPoint(x: gx, y: 4.5))
            line.addLine(to: CGPoint(x: gx, y: max(4.5, plotHeight - 10)))
            context.stroke(
                line,
                with: .color(.secondary.opacity(0.25)),
                style: StrokeStyle(lineWidth: 1, dash: [1, 3])
            )
        }

        // Apple's glyph bounds begin almost immediately below the plot. The
        // resolved text's center sits about 27% into the reserved axis band.
        let labelY = plotHeight + axisHeight * 0.27
        let labelStyle = Date.FormatStyle(date: .omitted, time: .shortened)

        let startText = Text(start.formatted(labelStyle))
            .font(.caption2)
            .foregroundStyle(.secondary)
        context.draw(startText, at: CGPoint(x: 0, y: labelY), anchor: .leading)

        let endText = Text(end.formatted(labelStyle))
            .font(.caption2)
            .foregroundStyle(.secondary)
        context.draw(endText, at: CGPoint(x: size.width, y: labelY), anchor: .trailing)

        for tick in ticks where calendar.component(.hour, from: tick).isMultiple(of: 2) {
            let tickX = x(tick)
            // Keep exact endpoint labels readable on short sessions.
            guard tickX > 50, tickX < size.width - 50 else { continue }
            let text = Text(tick.formatted(labelStyle))
                .font(.caption2)
                .foregroundStyle(.secondary)
            context.draw(text, at: CGPoint(x: tickX, y: labelY), anchor: .center)
        }
    }
}

/// Supplies colors sampled from the Apple Health sleep-stage palette.
private struct HRBSSleepColorProvider: SleepStageColorProvider {
    func color(for stage: SleepChartStage) -> Color {
        switch stage {
        case .awake: return Color(red: 248 / 255, green: 139 / 255, blue: 73 / 255)
        case .asleepREM: return Color(red: 128 / 255, green: 201 / 255, blue: 255 / 255)
        case .asleepCore: return Color(red: 93 / 255, green: 154 / 255, blue: 239 / 255)
        case .asleepDeep: return Color(red: 116 / 255, green: 75 / 255, blue: 207 / 255)
        case .asleepUnspecified: return Color(red: 93 / 255, green: 154 / 255, blue: 239 / 255)
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
