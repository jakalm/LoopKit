//
//  BasalRateChart.swift
//  LoopKitUI
//
//  Created by Claude Code for Period Detail View
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import SwiftCharts
import UIKit

public class BasalRateChart: ChartProviding {
    public init() {
        basalDoses = []
    }

    public var basalDoses: [DoseEntry] {
        didSet {
            basalPoints = []
            if let lastDose = basalDoses.max(by: { $0.endDate < $1.endDate }) {
                endDate = lastDose.endDate
            }
        }
    }

    private var basalPoints: [ChartPoint] = []

    /// The minimum range to display for basal rate values.
    private let basalDisplayRangePoints: [ChartPoint] = [0, 0.5].map {
        return ChartPoint(
            x: ChartAxisValue(scalar: 0),
            y: ChartAxisValueDouble($0)
        )
    }

    public private(set) var endDate: Date?
}

public extension BasalRateChart {
    func didReceiveMemoryWarning() {
        basalPoints = []
    }

    func generate(withFrame frame: CGRect, xAxisModel: ChartAxisModel, xAxisValues: [ChartAxisValue], axisLabelSettings: ChartLabelSettings, guideLinesLayerSettings: ChartGuideLinesLayerSettings, colors: ChartColorPalette, chartSettings: ChartSettings, labelsWidthY: CGFloat, gestureRecognizer: UIGestureRecognizer?, traitCollection: UITraitCollection, highlightedTimeRange: (start: Date, end: Date)?) -> Chart
    {
        // Generate chart points from basal doses
        if basalPoints.isEmpty {
            basalPoints = basalPointsFromDoses(basalDoses)
        }

        let yAxisValues = ChartAxisValuesStaticGenerator.generateYAxisValuesWithChartPoints(
            basalPoints + basalDisplayRangePoints,
            minSegmentCount: 2,
            maxSegmentCount: 4,
            multiple: 0.5,
            axisValueGenerator: { ChartAxisValueDouble($0, labelSettings: axisLabelSettings) },
            addPaddingSegmentIfEdge: false
        )

        let yAxisModel = ChartAxisModel(axisValues: yAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(labelsWidthY))

        let coordsSpace = ChartCoordsSpaceLeftBottomSingleAxis(chartSettings: chartSettings, chartFrame: frame, xModel: xAxisModel, yModel: yAxisModel)

        let (xAxisLayer, yAxisLayer, innerFrame) = (coordsSpace.xAxisLayer, coordsSpace.yAxisLayer, coordsSpace.chartInnerFrame)

        // Grid lines
        let gridLayer = ChartGuideLinesForValuesLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, settings: guideLinesLayerSettings, axisValuesX: Array(xAxisValues.dropFirst().dropLast()), axisValuesY: yAxisValues)

        // Highlighted time range overlay
        let highlightLayer = createHighlightLayer(xAxisLayer: xAxisLayer, yAxisLayer: yAxisLayer, highlightedTimeRange: highlightedTimeRange, innerFrame: innerFrame)

        // Basal rate line
        let lineModel = ChartLineModel(chartPoints: basalPoints, lineColor: colors.insulinTint, lineWidth: 2, animDuration: 0, animDelay: 0)
        let basalLine = ChartPointsLineLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, lineModels: [lineModel])

        // Basal rate fill
        let basalFill = ChartPointsFillsLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, fills: [ChartPointsFill(chartPoints: basalPoints, fillColor: colors.insulinTint.withAlphaComponent(0.3))])

        let layers: [ChartLayer?] = [
            gridLayer,
            xAxisLayer,
            yAxisLayer,
            highlightLayer,
            basalFill,
            basalLine,
        ]

        return Chart(frame: frame, innerFrame: innerFrame, settings: chartSettings, layers: layers.compactMap { $0 })
    }

    private func basalPointsFromDoses(_ doses: [DoseEntry]) -> [ChartPoint] {
        let dateFormatter = DateFormatter(timeStyle: .short)
        var points: [ChartPoint] = []

        for dose in doses.sorted(by: { $0.startDate < $1.startDate }) {
            let rate = dose.type == .suspend ? 0.0 : dose.unitsPerHour

            // Add point at start of dose segment
            points.append(ChartPoint(
                x: ChartAxisValueDate(date: dose.startDate, formatter: dateFormatter),
                y: ChartAxisValueDouble(rate)
            ))

            // Add point at end of dose segment
            points.append(ChartPoint(
                x: ChartAxisValueDate(date: dose.endDate, formatter: dateFormatter),
                y: ChartAxisValueDouble(rate)
            ))
        }

        return points
    }
}

public extension BasalRateChart {
    func setBasalDoses(_ doses: [DoseEntry]) {
        self.basalDoses = doses
    }
}
