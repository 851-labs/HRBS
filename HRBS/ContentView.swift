import SwiftUI

/// The app's main screen: a scrollable summary of pre-sleep heart rate and
/// sleep stages for the selected day, with a date picker in the navigation bar.
struct DashboardView: View {
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var isShowingDatePicker = false
    @State private var model = DashboardModel()

    private let calendar = Calendar.current

    private var isViewingToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: today)
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color.groupedBackground)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        dateNavigator
                    }
                }
                .sheet(isPresented: $isShowingDatePicker) {
                    datePickerSheet
                }
        }
        .task(id: selectedDate) {
            await model.load(for: selectedDate)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let day):
            ScrollView {
                VStack(spacing: 16) {
                    HeartRateCard(reading: day.heartRate)
                    SleepCard(session: day.sleep, age: day.age)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

        case .empty:
            ContentUnavailableView {
                Label("No Sleep Data", systemImage: "bed.double")
            } description: {
                Text("There's no sleep recorded for this day. Make sure HRBS is allowed to read Sleep and Heart Rate in Settings › Health › Data Access & Devices.")
            }
        }
    }

    // MARK: - Navigation bar date navigator

    private var dateNavigator: some View {
        HStack(spacing: 14) {
            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Button {
                isShowingDatePicker = true
            } label: {
                HStack(spacing: 5) {
                    Text(titleText)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
            }

            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isViewingToday)
        }
    }

    private var titleText: String {
        if isViewingToday {
            return "Today"
        }
        if calendar.isDate(selectedDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today) ?? today) {
            return "Yesterday"
        }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    // MARK: - Date picker sheet

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Day",
                selection: Binding(
                    get: { selectedDate },
                    set: { selectedDate = calendar.startOfDay(for: $0) }
                ),
                in: ...today,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal)
            .navigationTitle("Select Day")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func shift(by days: Int) {
        guard let newDate = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        if calendar.startOfDay(for: newDate) <= today {
            selectedDate = calendar.startOfDay(for: newDate)
        }
    }
}

#Preview {
    DashboardView()
}
