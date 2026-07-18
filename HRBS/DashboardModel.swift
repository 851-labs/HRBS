import SwiftUI

/// Loads a day's dashboard data, preferring HealthKit and falling back to
/// sample data on platforms where HealthKit isn't available. Shared across the
/// paged day views; each page requests its own date and keeps its own result.
@MainActor
@Observable
final class DashboardModel {
    enum LoadState {
        case loading
        case loaded(DayData)
        case empty
    }

    #if os(iOS)
    private let health = HealthDataStore()
    private var hasRequestedAuthorization = false
    #endif

    func result(for date: Date) async -> LoadState {
        #if os(iOS)
        if health.isAvailable {
            await ensureAuthorization()
            if let data = await health.dayData(for: date) {
                return .loaded(data)
            }
            return .empty
        } else {
            // e.g. running on a device without HealthKit — show sample data.
            return .loaded(SampleDataProvider.data(for: date))
        }
        #else
        return .loaded(SampleDataProvider.data(for: date))
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
