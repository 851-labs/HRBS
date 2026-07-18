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

    private let calendar = Calendar.current

    /// Points to plot for the current range (daily, or weekly-averaged for 6M).
    private var points: [HeartRateTrendPoint] {
        range.aggregatesWeekly ? Self.weeklyAveraged(rawPoints, calendar: calendar) : rawPoints
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
            rawPoints = await model.heartRateTrend(days: 182)
            isLoading = false
            resetScroll()
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
            ForEach(points) { point in
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
            switch range {
            case .week:
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            case .sixMonths:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: range.visibleSeconds)
        .chartScrollPosition(x: $scrollX)
        .chartScrollTargetBehavior(.paging)
        .chartXSelection(value: $selectedDate)
    }

    // MARK: - Derived values

    private var selectedPoint: HeartRateTrendPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var visiblePoints: [HeartRateTrendPoint] {
        let end = scrollX.addingTimeInterval(range.visibleSeconds)
        return points.filter { $0.date >= scrollX && $0.date < end }
    }

    private var visibleAverage: Int? {
        let values = visiblePoints.map(\.bpm)
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private var visibleRangeLabel: String {
        let end = scrollX.addingTimeInterval(range.visibleSeconds - 86_400)
        let start = scrollX
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var yDomain: ClosedRange<Int> {
        let values = points.map(\.bpm)
        guard let low = values.min(), let high = values.max() else { return 40...80 }
        return (low - 5)...(high + 5)
    }

    private func resetScroll() {
        let lastDay = calendar.startOfDay(for: points.last?.date ?? Date())
        scrollX = calendar.date(byAdding: .day, value: -(range.visibleDays - 1), to: lastDay) ?? lastDay
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
