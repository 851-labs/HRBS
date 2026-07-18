// Vendored from SleepChartKit — https://github.com/DanielJamesTronca/SleepChartKit
// Copyright (c) 2025 Daniel James Tronca. MIT License.
// See ThirdParty/SleepChartKit/LICENSE. Local change: type renamed
// `SleepStage` -> `SleepChartStage` to avoid clashing with the app's own type.

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

public enum SleepChartStage: Int, CaseIterable, Hashable {
    case awake = 0
    case asleepREM = 1
    case asleepCore = 2
    case asleepDeep = 3
    case asleepUnspecified = 4
    case inBed = 5

    #if canImport(HealthKit)
    @available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
    public init?(healthKitValue: HKCategoryValueSleepAnalysis) {
        switch healthKitValue {
        case .awake: self = .awake
        case .asleepREM: self = .asleepREM
        case .asleepCore: self = .asleepCore
        case .asleepDeep: self = .asleepDeep
        case .asleepUnspecified: self = .asleepUnspecified
        case .inBed: self = .inBed
        @unknown default: return nil
        }
    }

    @available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
    public var healthKitValue: HKCategoryValueSleepAnalysis {
        switch self {
        case .awake: return .awake
        case .asleepREM: return .asleepREM
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepUnspecified: return .asleepUnspecified
        case .inBed: return .inBed
        }
    }
    #endif

    public var defaultDisplayName: String {
        switch self {
        case .awake: return "Awake"
        case .asleepREM: return "REM"
        case .asleepCore: return "Light"
        case .asleepDeep: return "Deep"
        case .asleepUnspecified: return "Sleep"
        case .inBed: return "In Bed"
        }
    }

    public var sortOrder: Int { rawValue }
}
