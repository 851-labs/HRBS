import SwiftUI
import Charts

/// The "Trends" tab: charts the pre-sleep heart rate (HRBS) over the last 30 days.
struct HistoryView: View {
    @State private var model = DashboardModel()
    @State private var points: [HeartRateTrendPoint] = []
    @State private var isLoading = true

    private var averageBPM: Int? {
        guard !points.isEmpty else { return nil }
        return Int((Double(points.map(\.bpm).reduce(0, +)) / Double(points.count)).rounded())
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if points.isEmpty {
                    ContentUnavailableView {
                        Label("No Heart Rate Data", systemImage: "heart.slash")
                    } description: {
                        Text("There's no pre-sleep heart rate recorded over the last 30 days.")
                    }
                } else {
                    ScrollView {
                        trendCard
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.groupedBackground)
            .navigationTitle("Trends")
        }
        .task {
            points = await model.heartRateTrend(days: 30)
            isLoading = false
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Heart Rate Before Sleep")
                    .font(.headline)
                    .foregroundStyle(.red)
            }

            Text("Past 30 Days")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let averageBPM {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(averageBPM)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("avg BPM")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            chart
                .frame(height: 220)
                .padding(.top, 4)
        }
        .cardStyle()
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("BPM", point.bpm)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.red)

            PointMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("BPM", point.bpm)
            )
            .foregroundStyle(.red)
            .symbolSize(18)

            if let averageBPM {
                RuleMark(y: .value("Average", averageBPM))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bpm = value.as(Int.self) {
                        Text("\(bpm)")
                    }
                }
            }
        }
    }

    private var yDomain: ClosedRange<Int> {
        let values = points.map(\.bpm)
        guard let low = values.min(), let high = values.max() else { return 40...80 }
        return (low - 5)...(high + 5)
    }
}

#Preview {
    HistoryView()
}
