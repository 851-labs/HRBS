// Originally vendored from SleepChartKit — https://github.com/DanielJamesTronca/SleepChartKit
// Copyright (c) 2025 Daniel James Tronca. MIT License.
// See ThirdParty/SleepChartKit/LICENSE.
//
// The renderer below is a local rewrite modelled after Apple Health's sleep
// stages chart: narrow stage bands, softly glowing fills, and translucent
// gradient ribbons that carry color through vertical stage transitions.

import SwiftUI

public struct SleepTimelineGraph: View {
    let samples: [SleepSample]
    let colorProvider: SleepStageColorProvider

    public init(
        samples: [SleepSample],
        colorProvider: SleepStageColorProvider = DefaultSleepStageColorProvider()
    ) {
        self.samples = samples
        self.colorProvider = colorProvider
    }

    public var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let timeline = normalizedSamples
            guard let first = timeline.first, let last = timeline.last else { return }

            let duration = last.endDate.timeIntervalSince(first.startDate)
            guard duration > 0, size.width > 0, size.height > 0 else { return }

            let laneHeight = size.height / SleepChartConstants.stageRowCount
            let bandHeight = laneHeight * SleepChartConstants.bandHeightRatio

            func x(_ date: Date) -> CGFloat {
                CGFloat(date.timeIntervalSince(first.startDate) / duration) * size.width
            }

            func centerY(_ stage: SleepChartStage) -> CGFloat {
                (CGFloat(laneIndex(for: stage)) + 0.5) * laneHeight
            }

            // Transition ribbons sit behind the opaque stage blocks. The broad
            // bloom supplies Apple's soft color bridge; the narrow core keeps
            // short transitions legible without introducing gray bars.
            for pair in zip(timeline, timeline.dropFirst()) {
                let previous = pair.0
                let current = pair.1
                guard previous.stage != current.stage else { continue }

                let gap = current.startDate.timeIntervalSince(previous.endDate)
                guard gap <= SleepChartConstants.maximumConnectedGap else { continue }

                let transitionDate = gap > 0
                    ? previous.endDate.addingTimeInterval(gap / 2)
                    : current.startDate
                let transitionX = x(transitionDate)
                let fromY = centerY(previous.stage)
                let toY = centerY(current.stage)
                let fromColor = colorProvider.color(for: previous.stage)
                let toColor = colorProvider.color(for: current.stage)

                drawTransition(
                    context: &context,
                    centerX: transitionX,
                    fromY: fromY,
                    toY: toY,
                    bandHeight: bandHeight,
                    highStageIsAwake: laneIndex(for: previous.stage) == 0 ||
                        laneIndex(for: current.stage) == 0,
                    fromColor: fromColor,
                    toColor: toColor
                )
            }

            // Blocks are drawn last so their rounded shoulders mask the ends of
            // the connector ribbons and produce one continuous visual surface.
            for sample in timeline {
                let rawMinX = x(sample.startDate)
                let rawMaxX = x(sample.endDate)
                let rawWidth = max(0, rawMaxX - rawMinX)
                let width = max(SleepChartConstants.minimumBarWidth, rawWidth)
                let midX = (rawMinX + rawMaxX) / 2
                let rect = CGRect(
                    x: midX - width / 2,
                    y: centerY(sample.stage) - bandHeight / 2,
                    width: width,
                    height: bandHeight
                )
                drawStageBlock(
                    context: &context,
                    rect: rect,
                    color: colorProvider.color(for: sample.stage)
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages")
    }

    // MARK: - Data preparation

    /// HealthKit may return adjacent samples of the same stage. Apple renders
    /// these as a single uninterrupted block, so merge them before drawing.
    private var normalizedSamples: [SleepSample] {
        let hasSpecificStage = samples.contains { $0.stage != .inBed }
        let sorted = samples
            .filter { $0.endDate > $0.startDate }
            .filter { !hasSpecificStage || $0.stage != .inBed }
            .sorted {
                if $0.startDate == $1.startDate { return $0.endDate < $1.endDate }
                return $0.startDate < $1.startDate
            }

        var result: [SleepSample] = []
        for sample in sorted {
            guard let previous = result.last else {
                result.append(sample)
                continue
            }

            let gap = sample.startDate.timeIntervalSince(previous.endDate)
            if sample.stage == previous.stage,
               gap <= SleepChartConstants.maximumMergedGap {
                result[result.count - 1] = SleepSample(
                    stage: previous.stage,
                    startDate: previous.startDate,
                    endDate: max(previous.endDate, sample.endDate)
                )
            } else {
                result.append(sample)
            }
        }
        return result
    }

    private func laneIndex(for stage: SleepChartStage) -> Int {
        switch stage {
        case .awake: return 0
        case .asleepREM: return 1
        case .asleepCore, .asleepUnspecified, .inBed: return 2
        case .asleepDeep: return 3
        }
    }

    // MARK: - Drawing

    private func drawStageBlock(
        context: inout GraphicsContext,
        rect: CGRect,
        color: Color
    ) {
        let radius = min(
            SleepChartConstants.maximumCornerRadius,
            rect.height * SleepChartConstants.cornerRadiusRatio,
            rect.width / 2
        )
        let block = Path(roundedRect: rect, cornerRadius: radius)

        context.drawLayer { layer in
            layer.addFilter(.shadow(
                color: color.opacity(SleepChartConstants.blockGlowOpacity),
                radius: SleepChartConstants.blockGlowRadius
            ))
            layer.fill(block, with: .color(color))
        }

        // A faint light rim is visible around Apple Health's colored blocks.
        context.stroke(
            block,
            with: .color(.white.opacity(SleepChartConstants.blockRimOpacity)),
            lineWidth: SleepChartConstants.blockRimWidth
        )
    }

    private func drawTransition(
        context: inout GraphicsContext,
        centerX: CGFloat,
        fromY: CGFloat,
        toY: CGFloat,
        bandHeight: CGFloat,
        highStageIsAwake: Bool,
        fromColor: Color,
        toColor: Color
    ) {
        guard abs(toY - fromY) > 0.5 else { return }

        let bloom = transitionPath(
            centerX: centerX,
            fromY: fromY,
            toY: toY,
            bandHeight: bandHeight,
            highStageIsAwake: highStageIsAwake,
            width: SleepChartConstants.transitionBloomWidth
        )
        let core = transitionPath(
            centerX: centerX,
            fromY: fromY,
            toY: toY,
            bandHeight: bandHeight,
            highStageIsAwake: highStageIsAwake,
            width: SleepChartConstants.transitionCoreWidth
        )
        let start = CGPoint(x: centerX, y: min(fromY, toY))
        let end = CGPoint(x: centerX, y: max(fromY, toY))
        let colors = fromY < toY
            ? [fromColor, toColor]
            : [toColor, fromColor]

        context.fill(
            bloom,
            with: .linearGradient(
                Gradient(colors: colors.map { $0.opacity(SleepChartConstants.transitionBloomOpacity) }),
                startPoint: start,
                endPoint: end
            )
        )
        context.fill(
            core,
            with: .linearGradient(
                Gradient(colors: colors.map { $0.opacity(SleepChartConstants.transitionCoreOpacity) }),
                startPoint: start,
                endPoint: end
            )
        )
    }

    /// Apple anchors a transition to the timestamp edge and lets the ribbon
    /// flow beneath both adjacent segments. Opposing cubic shoulders taper the
    /// higher-stage block into a narrow stem, then flare into the lower stage.
    private func transitionPath(
        centerX: CGFloat,
        fromY: CGFloat,
        toY: CGFloat,
        bandHeight: CGFloat,
        highStageIsAwake: Bool,
        width: CGFloat
    ) -> Path {
        let highY = min(fromY, toY)
        let lowY = max(fromY, toY)
        // A descending transition belongs to the segment on the left; an
        // ascending transition belongs to the segment on the right.
        let side: CGFloat = fromY < toY ? -1 : 1
        let recentering = -side * width * SleepChartConstants.transitionSideRecenterRatio
        let timestampEdgeX = centerX + recentering
        let normalOuterX = timestampEdgeX + side * width
        let expandedOuterX = timestampEdgeX + side * (
            width + SleepChartConstants.transitionShoulderExpansion
        )
        let stageEdgeY = highY + bandHeight / 2
        let shoulderStartY = stageEdgeY + (
            highStageIsAwake ? SleepChartConstants.awakeShoulderHold : 0
        )
        let shoulderEndY = min(
            lowY,
            shoulderStartY + SleepChartConstants.transitionUpperShoulderDepth
        )
        let lowStageEdgeY = lowY - bandHeight / 2 -
            SleepChartConstants.transitionLowerShoulderLead
        let lowShoulderStartY = max(
            shoulderEndY,
            lowStageEdgeY - SleepChartConstants.transitionLowerShoulderDepth
        )
        let lowExpandedEdgeX = timestampEdgeX - side *
            SleepChartConstants.transitionLowerShoulderExpansion

        var path = Path()
        path.move(to: CGPoint(x: timestampEdgeX, y: highY))
        path.addLine(to: CGPoint(x: timestampEdgeX, y: lowShoulderStartY))
        path.addCurve(
            to: CGPoint(x: lowExpandedEdgeX, y: lowStageEdgeY),
            control1: CGPoint(
                x: timestampEdgeX,
                y: lowShoulderStartY + SleepChartConstants.transitionLowerShoulderDepth * 0.45
            ),
            control2: CGPoint(
                x: lowExpandedEdgeX,
                y: lowStageEdgeY - SleepChartConstants.transitionLowerShoulderDepth * 0.45
            )
        )
        path.addLine(to: CGPoint(x: lowExpandedEdgeX, y: lowY))
        path.addLine(to: CGPoint(x: normalOuterX, y: lowY))
        path.addLine(to: CGPoint(x: normalOuterX, y: shoulderEndY))
        path.addCurve(
            to: CGPoint(x: expandedOuterX, y: shoulderStartY),
            control1: CGPoint(
                x: normalOuterX,
                y: shoulderStartY + SleepChartConstants.transitionUpperShoulderDepth * 0.55
            ),
            control2: CGPoint(
                x: expandedOuterX,
                y: shoulderStartY + SleepChartConstants.transitionUpperShoulderDepth * 0.45
            )
        )
        path.addLine(to: CGPoint(x: expandedOuterX, y: highY))
        path.closeSubpath()
        return path
    }
}
