import SwiftUI

/// The app's main screen: a horizontally-paged set of days (swipe left/right to
/// move between dates, like Calendar), with a date picker in the navigation bar
/// that stays in sync with the current page.
struct DashboardView: View {
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var isShowingDatePicker = false
    @State private var model = DashboardModel()

    private let calendar = Calendar.current

    /// How many days back you can swipe.
    private static let historyLength = 120

    private var today: Date { calendar.startOfDay(for: Date()) }

    /// Oldest day first, today last, so swiping right goes back in time.
    private var dates: [Date] {
        (0..<Self.historyLength)
            .reversed()
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var earliestDate: Date { dates.first ?? today }

    private var isViewingToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: today)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedDate) {
                ForEach(dates, id: \.self) { date in
                    DayPage(date: date, model: model)
                        .tag(date)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    dateNavigator
                }
            }
            .sheet(isPresented: $isShowingDatePicker) {
                datePickerSheet
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
            .disabled(calendar.isDate(selectedDate, inSameDayAs: earliestDate))

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
                in: earliestDate...today,
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
        let day = calendar.startOfDay(for: newDate)
        guard day >= earliestDate, day <= today else { return }
        withAnimation {
            selectedDate = day
        }
    }
}

/// One swipeable day. Loads its own data so adjacent pages are ready as you swipe.
private struct DayPage: View {
    let date: Date
    let model: DashboardModel

    @State private var state: DashboardModel.LoadState = .loading

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.groupedBackground)
            .task(id: date) {
                state = await model.result(for: date)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()

        case .loaded(let day):
            ScrollView {
                VStack(spacing: 16) {
                    HeartRateCard(reading: day.heartRate)
                    SleepCard(session: day.sleep, age: day.age, baseline: day.baseline)
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
}

#Preview {
    DashboardView()
}
