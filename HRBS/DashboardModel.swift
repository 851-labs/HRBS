import SwiftUI

/// Loads a day's dashboard data, preferring HealthKit and falling back to
/// sample data on platforms where HealthKit isn't available.
@MainActor
@Observable
final class DashboardModel {
    enum LoadState {
        case loading
        case loaded(DayData)
        case empty
    }

    private(set) var state: LoadState = .loading

    #if os(iOS)
    private let health = HealthDataStore()
    private var hasRequestedAuthorization = false
    #endif

    func load(for date: Date) async {
        state = .loading

        #if os(iOS)
        if health.isAvailable {
            await ensureAuthorization()
            if let data = await health.dayData(for: date) {
                state = .loaded(data)
            } else {
                state = .empty
            }
        } else {
            // e.g. running on a device without HealthKit — show sample data.
            state = .loaded(SampleDataProvider.data(for: date))
        }
        #else
        state = .loaded(SampleDataProvider.data(for: date))
        #endif
    }

    #if os(iOS)
    private func ensureAuthorization() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        await health.requestAuthorization()
    }
    #endif
}
