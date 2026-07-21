// Vendored from SleepChartKit — https://github.com/DanielJamesTronca/SleepChartKit
// Copyright (c) 2025 Daniel James Tronca. MIT License.
// See ThirdParty/SleepChartKit/LICENSE. Trimmed to the constants used by the
// vendored timeline graph.

import Foundation
import SwiftUI

/// Scale-independent geometry tuned against Apple Health's sleep-stage chart.
public enum SleepChartConstants {
    public static let stageRowCount: CGFloat = 4
    public static let bandHeightRatio: CGFloat = 0.51
    public static let minimumBarWidth: CGFloat = 2.5
    public static let cornerRadiusRatio: CGFloat = 0.13
    public static let maximumCornerRadius: CGFloat = 4

    public static let transitionBloomWidth: CGFloat = 2.65
    public static let transitionCoreWidth: CGFloat = 1.5
    public static let transitionBloomOpacity: CGFloat = 0.05
    public static let transitionCoreOpacity: CGFloat = 0.23
    public static let transitionSideRecenterRatio: CGFloat = 0.55
    public static let transitionUpperShoulderDepth: CGFloat = 3
    public static let transitionLowerShoulderDepth: CGFloat = 2
    public static let transitionShoulderExpansion: CGFloat = 2
    public static let transitionLowerShoulderExpansion: CGFloat = 2.5
    public static let transitionLowerShoulderLead: CGFloat = 0.75
    public static let awakeShoulderHold: CGFloat = 1.25

    public static let blockGlowOpacity: CGFloat = 0.70
    public static let blockGlowRadius: CGFloat = 0.6
    public static let blockRimOpacity: CGFloat = 0.55
    public static let blockRimWidth: CGFloat = 0.9

    public static let maximumMergedGap: TimeInterval = 30
    public static let maximumConnectedGap: TimeInterval = 90
}
