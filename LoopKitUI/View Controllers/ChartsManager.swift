//
//  Chart.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/19/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import SwiftCharts
import UIKit


open class ChartsManager {

    private lazy var timeFormatter: DateFormatter = {
        // Use custom formatter if provided, otherwise use default
        if let customFormatter = self.customTimeFormatter {
            return customFormatter
        }

        let formatter = DateFormatter()
        let dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)!
        let isAmPmTimeFormat = dateFormat.firstIndex(of: "a") != nil
        formatter.dateFormat = isAmPmTimeFormat
            ? "h a"
            : "H:mm"
        return formatter
    }()

    private let customTimeFormatter: DateFormatter?

    public init(
        colors: ChartColorPalette,
        settings: ChartSettings,
        axisLabelFont: UIFont = .systemFont(ofSize: 14), // caption1, but hard-coded until axis can scale with type preference
        charts: [ChartProviding],
        traitCollection: UITraitCollection,
        customTimeFormatter: DateFormatter? = nil
    ) {
        self.colors = colors
        self.chartSettings = settings
        self.charts = charts
        self.traitCollection = traitCollection
        self.chartsCache = Array(repeating: nil, count: charts.count)
        self.customTimeFormatter = customTimeFormatter

        axisLabelSettings = ChartLabelSettings(font: axisLabelFont, fontColor: colors.axisLabel)

        guideLinesLayerSettings = ChartGuideLinesLayerSettings(linesColor: colors.grid)
    }

    // MARK: - Configuration

    private let colors: ChartColorPalette

    private let chartSettings: ChartSettings

    private let labelsWidthY: CGFloat = 30

    public let charts: [ChartProviding]

    /// The amount of horizontal space reserved for fixed margins
    public var fixedHorizontalMargin: CGFloat {
        return chartSettings.leading + chartSettings.trailing + labelsWidthY + chartSettings.labelsToAxisSpacingY
    }

    private let axisLabelSettings: ChartLabelSettings

    private let guideLinesLayerSettings: ChartGuideLinesLayerSettings

    public var gestureRecognizer: UIGestureRecognizer?

    public var highlightedTimeRange: (start: Date, end: Date)?

    // MARK: - UITraitEnvironment

    public var traitCollection: UITraitCollection

    public func didReceiveMemoryWarning() {

        for chart in charts {
            chart.didReceiveMemoryWarning()
        }

        xAxisValues = nil
    }

    // MARK: - Data

    /// The earliest date on the X-axis
    public var startDate = Date() {
        didSet {
            if startDate != oldValue {
                xAxisValues = nil

                // Set a new minimum end date
                endDate = startDate.addingTimeInterval(.hours(3))
            }
        }
    }

    /// The latest date on the X-axis
    private var endDate = Date() {
        didSet {
            if endDate != oldValue {
                xAxisValues = nil
            }
        }
    }

    /// The latest allowed date on the X-axis
    public var maxEndDate = Date.distantFuture {
        didSet {
            endDate = min(endDate, maxEndDate)
        }
    }

    /// Updates the endDate using a new candidate date
    ///
    /// Dates are rounded up to the next hour.
    ///
    /// - Parameter date: The new candidate date
    public func updateEndDate(_ date: Date) {
        if date > endDate {
            let components = DateComponents(minute: 0)
            endDate = min(
                maxEndDate,
                Calendar.current.nextDate(
                    after: date,
                    matching: components,
                    matchingPolicy: .strict,
                    direction: .forward
                ) ?? date
            )
        }
    }

    // MARK: - State

    private var xAxisValues: [ChartAxisValue]? {
        didSet {
            if let xAxisValues = xAxisValues, xAxisValues.count > 1 {
                xAxisModel = ChartAxisModel(axisValues: xAxisValues, lineColor: colors.axisLine, labelSpaceReservationMode: .fixed(20))
            } else {
                xAxisModel = nil
            }

            chartsCache.replaceAllElements(with: nil)
        }
    }

    private var xAxisModel: ChartAxisModel?

    private var chartsCache: [Chart?]

    // MARK: - Generators

    public func chart(atIndex index: Int, frame: CGRect) -> Chart? {
        if let chart = chartsCache[index], chart.frame != frame {
            chartsCache[index] = nil
        }

        if chartsCache[index] == nil, let xAxisModel = xAxisModel, let xAxisValues = xAxisValues {
            chartsCache[index] = charts[index].generate(withFrame: frame, xAxisModel: xAxisModel, xAxisValues: xAxisValues, axisLabelSettings: axisLabelSettings, guideLinesLayerSettings: guideLinesLayerSettings, colors: colors, chartSettings: chartSettings, labelsWidthY: labelsWidthY, gestureRecognizer: gestureRecognizer, traitCollection: traitCollection, highlightedTimeRange: highlightedTimeRange)
        }

        return chartsCache[index]
    }

    public func invalidateChart(atIndex index: Int) {
        chartsCache[index] = nil
    }

    // MARK: - Shared Axis

    private func generateXAxisValues() {
        if let endDate = charts.compactMap({ $0.endDate }).max() {
            updateEndDate(endDate)
        }

        let points = [
            ChartPoint(
                x: ChartAxisValueDate(date: startDate, formatter: timeFormatter),
                y: ChartAxisValue(scalar: 0)
            ),
            ChartPoint(
                x: ChartAxisValueDate(date: endDate, formatter: timeFormatter),
                y: ChartAxisValue(scalar: 0)
            )
        ]

        let segments = ceil(endDate.timeIntervalSince(startDate).hours)

        let xAxisValues = ChartAxisValuesStaticGenerator.generateXAxisValuesWithChartPoints(points,
            minSegmentCount: segments - 1,
            maxSegmentCount: segments + 1,
            multiple: TimeInterval(hours: 1),
            axisValueGenerator: {
                ChartAxisValueDate(
                    date: ChartAxisValueDate.dateFromScalar($0),
                    formatter: timeFormatter,
                    labelSettings: self.axisLabelSettings
                )
            },
            addPaddingSegmentIfEdge: false
        )
        xAxisValues.first?.hidden = true
        xAxisValues.last?.hidden = true

        self.xAxisValues = xAxisValues
    }

    /// Runs any necessary steps before rendering charts
    public func prerender() {
        if xAxisValues == nil {
            generateXAxisValues()
        }
    }
}

fileprivate extension Array {
    mutating func replaceAllElements(with element: Element) {
        self = Array(repeating: element, count: count)
    }
}

public protocol ChartProviding {
    /// Instructs the chart to clear its non-critical resources like caches
    func didReceiveMemoryWarning()

    /// The last date represented in the chart data
    var endDate: Date? { get }

    /// Creates a chart from the current data
    ///
    /// - Returns: A new chart object
    func generate(withFrame frame: CGRect,
        xAxisModel: ChartAxisModel,
        xAxisValues: [ChartAxisValue],
        axisLabelSettings: ChartLabelSettings,
        guideLinesLayerSettings: ChartGuideLinesLayerSettings,
        colors: ChartColorPalette,
        chartSettings: ChartSettings,
        labelsWidthY: CGFloat,
        gestureRecognizer: UIGestureRecognizer?,
        traitCollection: UITraitCollection,
        highlightedTimeRange: (start: Date, end: Date)?
    ) -> Chart
}

// MARK: - Highlighted Time Range Helper

extension ChartProviding {
    func createHighlightLayer(
        xAxisLayer: ChartAxisLayer,
        yAxisLayer: ChartAxisLayer,
        highlightedTimeRange: (start: Date, end: Date)?,
        innerFrame: CGRect
    ) -> ChartLayer? {
        guard let timeRange = highlightedTimeRange else {
            return nil
        }

        // Create chart points for the start and end of the highlighted range
        // Use the same date formatter used by the chart
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .none
        dateFormatter.timeStyle = .short

        let startPoint = ChartPoint(x: ChartAxisValueDate(date: timeRange.start, formatter: dateFormatter), y: ChartAxisValueDouble(0))
        let endPoint = ChartPoint(x: ChartAxisValueDate(date: timeRange.end, formatter: dateFormatter), y: ChartAxisValueDouble(0))

        return ChartPointsViewsLayer(xAxis: xAxisLayer.axis, yAxis: yAxisLayer.axis, chartPoints: [startPoint, endPoint], viewGenerator: { (chartPointModel, layer, chart) -> UIView? in
            // Only create the overlay view once for the first point
            guard chartPointModel.index == 0 else { return nil }

            // Get the screen location for the start point (current chartPointModel)
            let startX = chartPointModel.screenLoc.x

            // We need to manually calculate the end X position
            // Find the chart point model for the end point
            guard let endPointModel = layer.chartPointsModels.first(where: { $0.index == 1 }) else {
                return nil
            }
            let endX = endPointModel.screenLoc.x

            // Use the chart's content view bounds for full height coverage
            let contentBounds = chart.contentView.bounds
            let overlayView = UIView(frame: CGRect(x: startX, y: contentBounds.minY, width: endX - startX, height: contentBounds.height))
            overlayView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.15)
            overlayView.isUserInteractionEnabled = false

            // Add left border
            let leftBorder = CALayer()
            leftBorder.frame = CGRect(x: 0, y: 0, width: 2, height: overlayView.bounds.height)
            leftBorder.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.6).cgColor
            overlayView.layer.addSublayer(leftBorder)

            // Add right border
            let rightBorder = CALayer()
            rightBorder.frame = CGRect(x: overlayView.bounds.width - 2, y: 0, width: 2, height: overlayView.bounds.height)
            rightBorder.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.6).cgColor
            overlayView.layer.addSublayer(rightBorder)

            return overlayView
        })
    }
}
