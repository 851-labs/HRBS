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
        VStack(alignment: .leading, spacing: 10) {
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
private let barHeight: CGFloat = 16
/// Height reserved for the row; the optimal-range window fills this so it stands
/// taller than the bar, bracketing it above and below.
private let windowHeight: CGFloat = 26

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
    /// The recommended amount of time (in seconds) to spend in this stage per
    /// night, the way top sleep apps (e.g. Oura, Gentler) express it: an
    /// absolute duration target rather than a percentage. These are deliberately
    /// realistic for consumer wearables — Apple's sleep tracking reports deep
    /// sleep on the low side, so the deep target is Oura's ~45–90 min rather
    /// than a textbook 15–20% of an 8h night. Targets taper with age (deep and
    /// REM decline). Awake has no target. Falls back to ~30-year-old values.
    /// Because these are absolute, a short night still reads as "not enough".
    func optimalDurationRange(forAge age: Int?) -> ClosedRange<TimeInterval>? {
        let years = Double(min(max(age ?? 30, 18), 90))
        let over40 = max(0, years - 40) // most age-related decline starts here

        func minutes(_ low: Double, _ high: Double) -> ClosedRange<TimeInterval> {
            (max(15, low) * 60)...(max(30, high) * 60)
        }

        switch self {
        case .awake:
            return nil
        case .deep:
            // Oura's optimal deep window (~45–90 min), tapering with age.
            return minutes(45 - over40 * 0.6, 90 - over40 * 1.2)
        case .rem:
            // ~75–120 min, easing down slightly with age.
            return minutes(75 - over40 * 0.6, 120 - over40 * 0.8)
        case .core:
            // Light/core sleep is the bulk of the night (~3–4.5 h).
            return minutes(180, 270)
        }
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
