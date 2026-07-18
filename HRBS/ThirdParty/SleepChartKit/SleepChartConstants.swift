// Vendored from SleepChartKit — https://github.com/DanielJamesTronca/SleepChartKit
// Copyright (c) 2025 Daniel James Tronca. MIT License.
// See ThirdParty/SleepChartKit/LICENSE. Trimmed to the constants used by the
// vendored timeline graph.

import Foundation
import SwiftUI

/// Constants used by the vendored SleepChartKit timeline graph.
public enum SleepChartConstants {
    /// Number of sleep stage rows in the timeline. Local change: 5 -> 4, since
    /// the app collapses "unspecified" into core and never shows an "in bed"
    /// lane, so four lanes (Awake/REM/Core/Deep) fill the height like Apple.
    public static let stageRowCount: CGFloat = 4

    /// Minimum width for sleep stage bars to ensure visibility.
    public static let minimumBarWidth: CGFloat = 1

    /// Corner radius ratio for sleep stage bars (bar height / ratio).
    public static let barCornerRadiusRatio: CGFloat = 6

    /// Line width for stage connector curves.
    public static let connectorLineWidth: CGFloat = 1.5

    /// Opacity for stage connector curves.
    public static let connectorOpacity: CGFloat = 0.4

    /// Control point ratios for connector curve smoothness.
    public static let connectorControlPointRatio1: CGFloat = 0.3
    public static let connectorControlPointRatio2: CGFloat = 0.7
}
