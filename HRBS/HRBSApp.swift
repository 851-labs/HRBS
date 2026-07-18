import SwiftUI

@main
struct HRBSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// The app's root: a bottom tab bar with the per-day dashboard and the
/// historical trends view.
struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Day", systemImage: "bed.double.fill")
                }

            HistoryView()
                .tabItem {
                    Label("Trends", systemImage: "chart.xyaxis.line")
                }
        }
    }
}

#Preview {
    RootView()
}
