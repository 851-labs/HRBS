// Vendored from SleepChartKit — https://github.com/DanielJamesTronca/SleepChartKit
// Copyright (c) 2025 Daniel James Tronca. MIT License.
// See ThirdParty/SleepChartKit/LICENSE. Local change: `SleepStage` -> `SleepChartStage`.

import SwiftUI

/// A SwiftUI view that renders sleep data as a timeline graph with horizontal bars for each sleep stage.
///
/// This view displays sleep stages as colored horizontal bars positioned vertically by stage type,
/// with smooth connecting curves between stage transitions. Each bar's width represents the duration
/// of that sleep stage, and the vertical position indicates the stage type.
public struct SleepTimelineGraph: View {

    // MARK: - Properties

    /// The sleep samples to render in the timeline
    let samples: [SleepSample]

    /// Provider for sleep stage colors
    let colorProvider: SleepStageColorProvider

    // MARK: - Initialization

    /// Creates a new sleep timeline graph.
    ///
    /// - Parameters:
    ///   - samples: The sleep samples to display
    ///   - colorProvider: Provider for sleep stage colors (default: DefaultSleepStageColorProvider)
    public init(
        samples: [SleepSample],
        colorProvider: SleepStageColorProvider = DefaultSleepStageColorProvider()
    ) {
        self.samples = samples
        self.colorProvider = colorProvider
    }

    // MARK: - Layout Calculations

    /// Calculates the vertical offset for a sleep stage bar within the timeline.
    private func yOffsetForStage(_ stage: SleepChartStage, totalHeight: CGFloat, barHeight: CGFloat) -> CGFloat {
        let totalBarHeight = barHeight * SleepChartConstants.stageRowCount
        let totalSpacing = max(0, totalHeight - totalBarHeight)
        let spacing = totalSpacing / (SleepChartConstants.stageRowCount - 1)

        switch stage {
        case .awake:
            return 0
        case .asleepREM:
            return barHeight + spacing
        case .asleepCore:
            return (barHeight + spacing) * 2
        case .asleepDeep:
            return (barHeight + spacing) * 3
        case .asleepUnspecified, .inBed:
            // Local change: share the core lane rather than a 5th row.
            return (barHeight + spacing) * 2
        }
    }

    /// Calculates the height of individual sleep stage bars.
    private func barHeight(totalHeight: CGFloat) -> CGFloat {
        return totalHeight / SleepChartConstants.stageRowCount
    }

    // MARK: - Body

    public var body: some View {
        Canvas { context, size in
            // Ensure we have valid sample data
            guard let firstSample = samples.first,
                  let lastSample = samples.last else { return }

            // Calculate total time span for the sleep session
            let totalDuration = lastSample.endDate.timeIntervalSince(firstSample.startDate)
            guard totalDuration > 0 else { return }

            // Set up drawing dimensions
            let totalWidth = size.width
            let totalHeight = size.height
            let stageBarHeight = barHeight(totalHeight: totalHeight)

            // Track previous sample for drawing connectors
            var previousRect: CGRect?
            var previousStage: SleepChartStage?

            // Render each sleep sample as a bar with potential connectors
            for sample in samples {
                let currentStage = sample.stage

                // Skip "inBed" stages if other sleep stages exist (more specific data available)
                if currentStage == .inBed && samples.contains(where: { $0.stage != .inBed }) {
                    continue
                }

                // Calculate bar positioning and dimensions
                let sampleDuration = sample.duration
                let startTimeOffset = sample.startDate.timeIntervalSince(firstSample.startDate)

                let rectX = (startTimeOffset / totalDuration) * totalWidth
                let rectWidth = (sampleDuration / totalDuration) * totalWidth
                let rectY = yOffsetForStage(currentStage, totalHeight: totalHeight, barHeight: stageBarHeight)

                // Ensure minimum width for visibility
                let finalWidth = max(SleepChartConstants.minimumBarWidth, rectWidth)

                // Create and render the sleep stage bar
                let currentRect = CGRect(x: rectX, y: rectY, width: finalWidth, height: stageBarHeight)
                let cornerRadius = stageBarHeight / SleepChartConstants.barCornerRadiusRatio
                let path = Path(roundedRect: currentRect, cornerRadius: cornerRadius)
                context.fill(path, with: .color(colorProvider.color(for: currentStage)))

                // Draw connector curve between different sleep stages
                if let prevRect = previousRect,
                   let prevStage = previousStage,
                   currentStage != prevStage {
                    renderStageConnector(
                        context: context,
                        from: prevRect,
                        to: currentRect
                    )
                }

                // Update tracking variables for next iteration
                previousRect = currentRect
                previousStage = currentStage
            }
        }
    }

    // MARK: - Private Rendering Methods

    /// Renders a smooth curve connecting two sleep stage bars.
    private func renderStageConnector(
        context: GraphicsContext,
        from startRect: CGRect,
        to endRect: CGRect
    ) {
        let startPoint = CGPoint(x: startRect.maxX, y: startRect.midY)
        let endPoint = CGPoint(x: endRect.minX, y: endRect.midY)

        // Calculate control points for smooth Bézier curve
        let controlPoint1 = CGPoint(
            x: startPoint.x + (endPoint.x - startPoint.x) * SleepChartConstants.connectorControlPointRatio1,
            y: startPoint.y
        )
        let controlPoint2 = CGPoint(
            x: startPoint.x + (endPoint.x - startPoint.x) * SleepChartConstants.connectorControlPointRatio2,
            y: endPoint.y
        )

        // Create and draw the connector curve
        var connectorPath = Path()
        connectorPath.move(to: startPoint)
        connectorPath.addCurve(to: endPoint, control1: controlPoint1, control2: controlPoint2)

        context.stroke(
            connectorPath,
            with: .color(.gray.opacity(SleepChartConstants.connectorOpacity)),
            lineWidth: SleepChartConstants.connectorLineWidth
        )
    }
}
