// Vendored from SleepChartKit — https://github.com/DanielJamesTronca/SleepChartKit
// Copyright (c) 2025 Daniel James Tronca. MIT License.
// See ThirdParty/SleepChartKit/LICENSE. Local change: `SleepStage` -> `SleepChartStage`.

import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

public protocol SleepStageColorProvider {
    func color(for stage: SleepChartStage) -> Color

    #if canImport(HealthKit)
    @available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
    func color(for healthKitValue: HKCategoryValueSleepAnalysis) -> Color
    #endif
}

#if canImport(HealthKit)
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public extension SleepStageColorProvider {
    func color(for healthKitValue: HKCategoryValueSleepAnalysis) -> Color {
        guard let stage = SleepChartStage(healthKitValue: healthKitValue) else { return .gray }
        return color(for: stage)
    }
}
#endif

public struct DefaultSleepStageColorProvider: SleepStageColorProvider {
    public init() {}

    public func color(for stage: SleepChartStage) -> Color {
        switch stage {
        case .awake: return .orange
        case .asleepREM: return .cyan
        case .asleepCore: return .blue
        case .asleepDeep: return .indigo
        case .asleepUnspecified: return .purple
        case .inBed: return .gray
        }
    }
}
