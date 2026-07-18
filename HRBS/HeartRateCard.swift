import SwiftUI

/// Shows the resting heart rate captured five minutes before falling asleep,
/// styled like a metric card in Apple Health.
struct HeartRateCard: View {
    let reading: HeartRateReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Heart Rate")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
            }

            Text("5 minutes before falling asleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let reading {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(reading.bpm)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                    Text("BPM")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(reading.timestamp, format: .dateTime.weekday(.wide).hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("—")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("BPM")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("No heart rate recorded before sleep")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }
}

#Preview {
    HeartRateCard(reading: HeartRateReading(bpm: 58, timestamp: Date()))
        .padding()
        .background(Color.groupedBackground)
}
