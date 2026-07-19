import SwiftUI
import Charts

/// The bucket size for the trends chart, mirroring Apple Health's W / M / 6M.
enum TrendRange: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case sixMonths = "6M"

    var id: String { rawValue }

    /// Number of days visible at once.
    var visibleDays: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 182
        }
    }

    var visibleSeconds: TimeInterval { Double(visibleDays) * 86_400 }

    /// Aggregates daily readings into weekly averages for the 6-month view.
    var aggregatesWeekly: Bool { self == .sixMonths }
}

/// The "Trends" tab: pre-sleep heart rate (HRBS) over time, styled like the
/// Apple Health detail charts — scrollable/paged history, drag-to-scrub
/// tooltips, and a W / M / 6M range selector.
struct HistoryView: View {
    @State private var model = DashboardModel()
    @State private var rawPoints: [HeartRateTrendPoint] = []
    @State private var isLoading = true

    @State private var range: TrendRange = .week
    @State private var scrollX = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate: Date?

    /// Oldest day we've queried so far; older chunks load as you scroll back.
    @State private var earliestLoaded = Calendar.current.startOfDay(for: Date())
    @State private var isLoadingMore = false
    @State private var reachedOldest = false

    private let calendar = Calendar.current
    private static let initialDays = 365
    private static let chunkDays = 365

    private var today: Date { calendar.startOfDay(for: Date()) }

    // Derived data, cached so it isn't recomputed on every scroll tick.
    // Rebuilt by `rebuildDerived()` when rawPoints or range change.

    /// Points for the current range (daily, or weekly-averaged for 6M).
    @State private var displayPoints: [HeartRateTrendPoint] = []
    /// Full loaded data extent; defines the scrollable width via chartXScale.
    @State private var xDomain: ClosedRange<Date> = Calendar.current.startOfDay(for: Date())...Date()
    @State private var yDomain: ClosedRange<Int> = 40...80
    /// The date span whose points are actually plotted (visible window plus a
    /// couple of window-widths of buffer on each side).
    @State private var renderWindow: ClosedRange<Date> = .distantPast ... .distantFuture
    /// Explicit X-axis mark dates within the render window (see recomputeAxisDates).
    @State private var axisDates: [Date] = []

    /// Rebuilds everything derived from `rawPoints` + `range`. Called after the
    /// initial load, after each older chunk is prepended, and on range change.
    private func rebuildDerived() {
        displayPoints = range.aggregatesWeekly
            ? Self.weeklyAveraged(rawPoints, calendar: calendar)
            : rawPoints

        if let first = displayPoints.first?.date, let last = displayPoints.last?.date, first < last {
            xDomain = first...last
        } else {
            xDomain = (calendar.date(byAdding: .day, value: -(range.visibleDays - 1), to: today) ?? today)...today
        }

        let values = displayPoints.map(\.bpm)
        if let low = values.min(), let high = values.max() {
            yDomain = (low - 5)...(high + 5)
        } else {
            yDomain = 40...80
        }

        // xDomain may have grown (older chunk prepended) — keep axis in sync.
        recomputeAxisDates()
    }

    /// Re-centers the render window on `scrollX`, but only once scroll has left
    /// the inner hysteresis band (± 1 window beyond the visible region), so the
    /// chart's ForEach identity stays stable during a fling.
    private func updateRenderWindowIfNeeded(force: Bool = false) {
        let window = range.visibleSeconds
        let innerLow = scrollX.addingTimeInterval(-window)
        let innerHigh = scrollX.addingTimeInterval(2 * window) // visible + 1 window after
        if !force, renderWindow.contains(innerLow), renderWindow.contains(innerHigh) { return }
        renderWindow = scrollX.addingTimeInterval(-2 * window)...scrollX.addingTimeInterval(3 * window)
        recomputeAxisDates()
    }

    /// Explicit X-axis mark dates, confined to the render window. A stride-based
    /// `AxisMarks(values: .stride(by: .day))` generates marks across the entire
    /// scrollable domain (365+ per loaded year in W) and re-evaluates them on
    /// every scroll tick — measured at ~280ms/frame on an iPhone 14 Pro, which
    /// made W-scrolling run at a few fps. Explicit values keep it at ~35 marks.
    private func recomputeAxisDates() {
        let lo = max(renderWindow.lowerBound, xDomain.lowerBound)
        let hi = min(renderWindow.upperBound, xDomain.upperBound)
        guard lo <= hi else {
            axisDates = []
            return
        }

        var dates: [Date] = []
        var date: Date
        let step: (Date) -> Date?
        switch range {
        case .week:
            date = calendar.startOfDay(for: lo)
            step = { self.calendar.date(byAdding: .day, value: 1, to: $0) }
        case .month:
            date = calendar.dateInterval(of: .weekOfYear, for: lo)?.start ?? calendar.startOfDay(for: lo)
            step = { self.calendar.date(byAdding: .day, value: 7, to: $0) }
        case .sixMonths:
            date = calendar.dateInterval(of: .month, for: lo)?.start ?? calendar.startOfDay(for: lo)
            step = { self.calendar.date(byAdding: .month, value: 1, to: $0) }
        }
        while date <= hi {
            dates.append(date)
            guard let next = step(date), next > date else { break }
            date = next
        }
        axisDates = dates
    }

    /// Index of the first point at or after `date` (binary search; `points` is sorted).
    private static func lowerBound(_ points: [HeartRateTrendPoint], _ date: Date) -> Int {
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].date < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Points inside the render window, overscanning 2 points past each edge so
    /// the Catmull-Rom control points at the (offscreen) edges stay identical.
    private var plottedPoints: ArraySlice<HeartRateTrendPoint> {
        let low = Self.lowerBound(displayPoints, renderWindow.lowerBound)
        let high = Self.lowerBound(displayPoints, renderWindow.upperBound)
        return displayPoints[max(0, low - 2)..<min(displayPoints.count, high + 2)]
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rawPoints.isEmpty {
                    ContentUnavailableView {
                        Label("No Heart Rate Data", systemImage: "heart.slash")
                    } description: {
                        Text("There's no pre-sleep heart rate recorded yet.")
                    }
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.groupedBackground)
            .navigationTitle("Trends")
        }
        .task {
            let from = calendar.date(byAdding: .day, value: -(Self.initialDays - 1), to: today) ?? today
            earliestLoaded = from
            rawPoints = await model.heartRateTrend(from: from, to: today)
            isLoading = false
            rebuildDerived()
            resetScroll()
        }
        .onChange(of: scrollX) {
            updateRenderWindowIfNeeded()
            loadOlderIfNeeded()
        }
    }

    /// Fetches an older chunk of history when the user scrolls near the start,
    /// going back until HealthKit has no more data.
    private func loadOlderIfNeeded() {
        guard !isLoadingMore, !reachedOldest else { return }
        // Trigger while still a few windows away from the oldest data, so older
        // chunks arrive before the render buffer reaches the data edge.
        guard scrollX <= earliestLoaded.addingTimeInterval(range.visibleSeconds * 3) else { return }

        isLoadingMore = true
        let newTo = calendar.date(byAdding: .day, value: -1, to: earliestLoaded) ?? earliestLoaded
        let newFrom = calendar.date(byAdding: .day, value: -Self.chunkDays, to: newTo) ?? newTo

        Task {
            let older = await model.heartRateTrend(from: newFrom, to: newTo)
            earliestLoaded = newFrom
            if older.isEmpty {
                reachedOldest = true
            } else {
                rawPoints = (older + rawPoints).sorted { $0.date < $1.date }
                rebuildDerived()
            }
            isLoadingMore = false
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            Picker("Range", selection: $range) {
                ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: range) {
                selectedDate = nil
                rebuildDerived()
                resetScroll()
            }

            VStack(alignment: .leading, spacing: 14) {
                header
                chart
                    .frame(height: 240)
            }
            .cardStyle()
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    // MARK: - Header (summary or scrubbed selection)

    @ViewBuilder
    private var header: some View {
        if let selected = selectedPoint {
            VStack(alignment: .leading, spacing: 2) {
                Text("HEART RATE BEFORE SLEEP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                valueText(selected.bpm)
                Text(selected.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("AVERAGE")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                valueText(visibleAverage)
                Text(visibleRangeLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valueText(_ bpm: Int?) -> Text {
        if let bpm {
            return Text("\(bpm)").font(.system(size: 34, weight: .bold, design: .rounded))
                + Text(" BPM").font(.subheadline.weight(.semibold)).foregroundColor(.secondary)
        }
        return Text("—").font(.system(size: 34, weight: .bold, design: .rounded))
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(plottedPoints) { point in
                LineMark(x: .value("Date", point.date), y: .value("BPM", point.bpm))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.red)

                PointMark(x: .value("Date", point.date), y: .value("BPM", point.bpm))
                    .foregroundStyle(.red)
                    .symbolSize(range == .week ? 22 : 10)
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(.secondary.opacity(0.3))
                PointMark(x: .value("Date", selected.date), y: .value("BPM", selected.bpm))
                    .foregroundStyle(.red)
                    .symbolSize(80)
            }
        }
        // The explicit X domain keeps the scrollable extent at the full loaded
        // history even though only `plottedPoints` are rendered.
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bpm = value.as(Int.self) { Text("\(bpm)") }
                }
            }
        }
        .chartXAxis {
            // Explicit values, not `.stride(by:)`: a stride generates marks over
            // the entire scrollable domain on every scroll tick (see
            // recomputeAxisDates), which is what made the W bucket unusable.
            switch range {
            case .week:
                AxisMarks(values: axisDates) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            case .month:
                AxisMarks(values: axisDates) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            case .sixMonths:
                AxisMarks(values: axisDates) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: range.visibleSeconds)
        .chartScrollPosition(x: $scrollX)
        .chartScrollTargetBehavior(scrollBehavior)
        .chartXSelection(value: $selectedDate)
        // Recreate the chart when the range changes: the scroll target behavior
        // is captured by the underlying scroll view and doesn't update in place,
        // so without this the previous range's snap rule stays active.
        .id(range)
    }

    // MARK: - Derived values

    /// Nearest point to the scrubbed date (binary search on the sorted array).
    private var selectedPoint: HeartRateTrendPoint? {
        guard let selectedDate, !displayPoints.isEmpty else { return nil }
        let index = Self.lowerBound(displayPoints, selectedDate)
        var best = displayPoints[min(index, displayPoints.count - 1)]
        if index > 0 {
            let before = displayPoints[index - 1]
            if abs(before.date.timeIntervalSince(selectedDate)) < abs(best.date.timeIntervalSince(selectedDate)) {
                best = before
            }
        }
        return best
    }

    private var visibleSlice: ArraySlice<HeartRateTrendPoint> {
        let low = Self.lowerBound(displayPoints, scrollX)
        let high = Self.lowerBound(displayPoints, scrollX.addingTimeInterval(range.visibleSeconds))
        return displayPoints[low..<high]
    }

    private var visibleAverage: Int? {
        let slice = visibleSlice
        guard !slice.isEmpty else { return nil }
        return Int((Double(slice.reduce(0) { $0 + $1.bpm }) / Double(slice.count)).rounded())
    }

    private var visibleRangeLabel: String {
        let end = scrollX.addingTimeInterval(range.visibleSeconds - 86_400)
        let start = scrollX
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// Lands scroll deceleration on week-start boundaries (the locale's first
    /// weekday) for every range. `limitBehavior: .never` preserves fling
    /// momentum — `.automatic` limits travel distance in compact width, which
    /// is what made an earlier `majorAlignment` experiment feel paged/slow.
    ///
    /// M deliberately snaps to week starts, not month starts: month-boundary
    /// targets are ~30 days apart, and after a free-momentum deceleration the
    /// chart won't correct across up to half a screen, so it rests on a day
    /// boundary instead (verified empirically). Week starts also line up with
    /// M's weekly axis gridlines. 6M's weekly-averaged points sit exactly on
    /// week starts, so the same alignment fits there too.
    private var scrollBehavior: ValueAlignedChartScrollTargetBehavior {
        .valueAligned(
            matching: DateComponents(hour: 0, weekday: calendar.firstWeekday),
            limitBehavior: .never
        )
    }

    private func resetScroll() {
        let lastDay = calendar.startOfDay(for: displayPoints.last?.date ?? Date())
        scrollX = calendar.date(byAdding: .day, value: -(range.visibleDays - 1), to: lastDay) ?? lastDay
        updateRenderWindowIfNeeded(force: true)
    }

    // MARK: - Aggregation

    static func weeklyAveraged(_ points: [HeartRateTrendPoint], calendar: Calendar) -> [HeartRateTrendPoint] {
        let groups = Dictionary(grouping: points) { point in
            calendar.dateInterval(of: .weekOfYear, for: point.date)?.start ?? point.date
        }
        return groups.map { weekStart, weekPoints in
            let avg = Double(weekPoints.map(\.bpm).reduce(0, +)) / Double(weekPoints.count)
            return HeartRateTrendPoint(date: weekStart, bpm: Int(avg.rounded()))
        }
        .sorted { $0.date < $1.date }
    }
}

#Preview {
    HistoryView()
}
