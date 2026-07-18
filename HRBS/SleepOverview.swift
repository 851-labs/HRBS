import SwiftUI

/// The "Overview" section shown beneath the sleep chart. Each stage gets a
/// hatched track with a colored fill sized to its share of the night, an
/// "optimal range" window, and its percentage and duration. Mirrors the
/// Apple Health sleep detail layout.
struct SleepOverview: View {
    let session: SleepSession
    /// The sleeper's age, used to age-adjust the optimal ranges. Falls back to
    /// young-adult defaults when unavailable.
    var age: Int? = nil

    private var timeInBed: TimeInterval {
        session.segments.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Overview")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(SleepStage.displayOrder) { stage in
                let duration = session.duration(for: stage)
                // Every stage is shown as a share of total time in bed, so the
                // four rows sum to 100% — matching how other sleep apps report it.
                let fraction = timeInBed > 0 ? duration / timeInBed : 0
                StageOverviewRow(
                    stage: stage,
                    fraction: fraction,
                    duration: duration,
                    optimal: optimalWindow(for: stage)
                )
            }
        }
    }

    /// The optimal-range window as a fraction of the bar (time in bed). The
    /// target is an absolute duration, so on a short night it lands further
    /// right than the actual fill — flagging that you didn't get enough.
    private func optimalWindow(for stage: SleepStage) -> ClosedRange<Double>? {
        guard timeInBed > 0, let target = stage.optimalDurationRange(forAge: age) else { return nil }
        let lower = min(1, target.lowerBound / timeInBed)
        let upper = min(1, target.upperBound / timeInBed)
        guard upper > lower else { return nil }
        return lower...upper
    }
}

/// Shared rounding for the track, fill, and range window. Deliberately small so
/// the bars read as rounded rectangles rather than pills.
private let barCornerRadius: CGFloat = 6
/// Height of the colored bar itself.
private let barHeight: CGFloat = 20
/// Height reserved for the row; the optimal-range window fills this so it stands
/// taller than the bar, bracketing it above and below.
private let windowHeight: CGFloat = 30

private struct StageOverviewRow: View {
    let stage: SleepStage
    let fraction: Double
    let duration: TimeInterval
    let optimal: ClosedRange<Double>?

    var body: some View {
        HStack(spacing: 8) {
            Text(stage.rawValue)
                .font(.footnote)
                .frame(width: 44, alignment: .leading)

            StageBar(stage: stage, fraction: fraction, optimal: optimal)
                .frame(height: windowHeight)
                .frame(maxWidth: .infinity)

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 32, alignment: .trailing)

            Text(duration.compactDurationString)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 54, alignment: .trailing)
        }
    }
}

/// A single stage's bar: a hatched rounded-rectangle track, a colored fill, and
/// an optional optimal-range window drawn on top.
private struct StageBar: View {
    let stage: SleepStage
    let fraction: Double
    let optimal: ClosedRange<Double>?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            // ZStack is windowHeight tall; the track and fill are barHeight and
            // centered, while the window fills the full height so it brackets the
            // bar above and below.
            ZStack(alignment: .leading) {
                shape
                    .fill(Color.gray.opacity(0.05))
                    .overlay {
                        DiagonalHatch(spacing: 6)
                            .stroke(Color.gray.opacity(0.09), lineWidth: 2.5)
                            .clipShape(shape)
                    }
                    .frame(height: barHeight)

                shape
                    .fill(stage.color)
                    .frame(width: max(width * fraction, barHeight * 0.6), height: barHeight)

                if let optimal {
                    OptimalRangeWindow()
                        .frame(width: width * (optimal.upperBound - optimal.lowerBound), height: windowHeight)
                        .offset(x: width * optimal.lowerBound)
                }
            }
            .frame(height: geo.size.height)
        }
    }
}

/// The translucent window with dashed left/right edges marking a healthy range.
private struct OptimalRangeWindow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.gray.opacity(0.16))
            .overlay(alignment: .leading) { edge }
            .overlay(alignment: .trailing) { edge }
    }

    private var edge: some View {
        VerticalLine()
            .stroke(Color.gray.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            .frame(width: 2)
    }
}

// MARK: - Shapes

/// Diagonal (45°) parallel lines used to give the track its hatched texture.
private struct DiagonalHatch: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}

private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        return path
    }
}

// MARK: - Stage metadata

extension SleepStage {
    /// An age-adjusted healthy share of a full night for this stage, as a
    /// fraction of total sleep. A documented approximation of the age-related
    /// trends in Ohayon et al. (2004): deep sleep declines ~2% per decade
    /// (leveling off after ~60), REM dips slightly, and core/light rises to
    /// compensate. Awake has no target. Falls back to ~30-year-old values.
    private func optimalShareOfSleep(forAge age: Int?) -> ClosedRange<Double>? {
        let years = Double(min(max(age ?? 30, 18), 90))
        let leveled = min(years, 60) // deep/core changes plateau after ~60

        func band(midpointPercent: Double, halfWidthPercent: Double) -> ClosedRange<Double> {
            let low = max(0, (midpointPercent - halfWidthPercent) / 100)
            let high = min(1, (midpointPercent + halfWidthPercent) / 100)
            return low...high
        }

        switch self {
        case .awake:
            return nil
        case .deep:
            let midpoint = max(8, 20 - 0.2 * (leveled - 25))
            return band(midpointPercent: midpoint, halfWidthPercent: 4)
        case .rem:
            let midpoint = max(15, 23 - 0.06 * (years - 25))
            return band(midpointPercent: midpoint, halfWidthPercent: 3)
        case .core:
            let midpoint = min(60, 50 + 0.2 * (leveled - 25))
            return band(midpointPercent: midpoint, halfWidthPercent: 5)
        }
    }

    /// The recommended amount of time (in seconds) to spend in this stage per
    /// night, the way top sleep apps (e.g. Oura) express it: an absolute
    /// duration target rather than a percentage. Derived by applying the
    /// age-adjusted share to a healthy reference sleep duration (~8h, a little
    /// less for older adults). Because it's an absolute target, a short night
    /// correctly reads as "not enough" even when the proportions look normal.
    func optimalDurationRange(forAge age: Int?) -> ClosedRange<TimeInterval>? {
        guard let share = optimalShareOfSleep(forAge: age) else { return nil }
        let years = min(max(age ?? 30, 18), 90)
        let referenceSleep: TimeInterval = (years >= 65 ? 7.5 : 8.0) * 3600
        return (share.lowerBound * referenceSleep)...(share.upperBound * referenceSleep)
    }
}

extension TimeInterval {
    /// Compact duration used by the overview, e.g. "1h 22m", "1h", "45m".
    var compactDurationString: String {
        let totalMinutes = Int((self / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }
}

#Preview {
    SleepCard(session: SampleDataProvider.data(for: Date()).sleep)
        .padding()
        .background(Color.groupedBackground)
}
