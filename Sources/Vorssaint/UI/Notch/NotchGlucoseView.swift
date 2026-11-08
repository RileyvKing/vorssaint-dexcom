// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Glucose page: the reading and its direction, when it was last
/// confirmed, and the day's shape. Settings and the refresh live in the
/// island's top row.
struct NotchGlucoseView: View {
    let size: CGSize
    @ObservedObject private var glucose = GlucoseService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    @AppStorage(DefaultsKey.notchGlucoseLowThreshold) private var lowThreshold = GlucoseTargets.defaultLow
    @AppStorage(DefaultsKey.notchGlucoseHighThreshold) private var highThreshold = GlucoseTargets.defaultHigh
    private var text: NotchGlucoseStrings { FeatureStrings.notchGlucose(l10n.language) }
    private var targets: GlucoseTargets { GlucoseTargets(low: lowThreshold, high: highThreshold) }

    var body: some View {
        Group {
            if !glucose.isConfigured && !preview {
                setup
            } else if let reading = glucose.reading {
                content(reading)
            } else if preview {
                content(Self.sampleReading, history: Self.sampleHistory)
            } else {
                unavailable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if !preview { glucose.pageVisible = true } }
        .onDisappear { if !preview { glucose.pageVisible = false } }
        .notchBand(trailing: {
            if !preview {
                NotchIconButton(symbol: glucose.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                                title: text.refresh) { glucose.retryNow() }
                    .disabled(glucose.isRefreshing || !glucose.isConfigured)
                NotchIconButton(symbol: "gearshape", title: l10n.s.menuSettings) {
                    NotchService.shared.openSettings()
                }
            }
        })
    }

    private func content(_ reading: GlucoseReading) -> some View {
        content(reading, history: glucose.history)
    }

    private func content(_ reading: GlucoseReading, history: [GlucoseReading]) -> some View {
        VStack(alignment: .leading, spacing: NotchLayout.rowSpacing) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reading.displayText)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GlucoseText.tint(reading, targets: targets))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let symbol = reading.trend?.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(GlucoseText.tint(reading, targets: targets))
                            .accessibilityHidden(true)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(text.unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    status(reading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(NotchControlSurface(cornerRadius: 16, interactive: false))

            GlucoseSparkline(readings: history, targets: targets,
                             unit: text.unit, label: text.title)
                .frame(maxHeight: .infinity)
                .modifier(NotchControlSurface(cornerRadius: 16, interactive: false))

            if size.height > 112 {
                Text(text.notMedical)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func status(_ reading: GlucoseReading) -> some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            Text(statusText(reading, now: context.date))
                .font(.caption)
                .foregroundStyle(GlucoseSupport.isFresh(reading, now: context.date) ? Color.secondary : Color.orange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(statusText(reading, now: context.date))
        }
    }

    private func statusText(_ reading: GlucoseReading, now: Date) -> String {
        let fresh = GlucoseSupport.isFresh(reading, now: now)
        if let error = glucose.lastError, !fresh {
            if error == .noReadings { return text.noReading }
            return text.error(error)
        }
        if fresh {
            return text.updated(GlucoseText.age(reading.recordedAt, now: now, language: l10n.language))
        }
        return text.stale
    }

    private var setup: some View {
        NotchEmptyView(symbol: NotchModule.glucose.symbol, message: text.credentialsMissing) {
            NotchPillButton(title: text.configure, prominent: true) {
                NotchService.shared.openSettings()
            }
        }
    }

    @ViewBuilder private var unavailable: some View {
        if let error = glucose.lastError {
            NotchEmptyView(symbol: "exclamationmark.triangle",
                           message: text.error(error)) {
                NotchPillButton(title: text.refresh, prominent: true) { glucose.retryNow() }
            }
        } else {
            NotchEmptyView(symbol: NotchModule.glucose.symbol, message: text.noReading) {
                NotchPillButton(title: text.refresh, prominent: true) { glucose.retryNow() }
            }
        }
    }

    // The Settings preview has no reading of its own, so it shows the shape
    // the page takes with one, clearly labelled as a preview.
    static let sampleReading = GlucoseReading(value: 142, trend: .fortyFiveUp,
                                              recordedAt: Date().addingTimeInterval(-120))
    static let sampleHistory: [GlucoseReading] = (0..<18).map { index in
        let value = 112 + Int((Double(index) * 1.8).rounded())
        return GlucoseReading(value: value, trend: .fortyFiveUp,
                              recordedAt: Date().addingTimeInterval(-Double(17 - index) * 300))
    }
}

/// The day's readings as a line, the latest point marked, and a faint band
/// for the usual in-range values. Drawn with Canvas because the app keeps no
/// charting dependency.
private struct GlucoseSparkline: View {
    let readings: [GlucoseReading]
    let targets: GlucoseTargets
    let unit: String
    let label: String

    var body: some View {
        let points = plotted
        ZStack(alignment: .topLeading) {
            if points.count >= 2 {
                Canvas { context, size in
                    let rect = CGRect(x: 30, y: 7, width: max(1, size.width - 37), height: max(1, size.height - 14))
                    func x(_ date: Date) -> CGFloat {
                        guard let first = points.first?.date, let last = points.last?.date,
                              last > first else { return rect.midX }
                        return rect.minX + CGFloat(date.timeIntervalSince(first) / last.timeIntervalSince(first)) * rect.width
                    }
                    func y(_ value: Double) -> CGFloat {
                        let clamped = min(400, max(40, value))
                        return rect.maxY - CGFloat((clamped - 40) / 360) * rect.height
                    }
                    func thresholdLabel(_ value: Int, at position: CGFloat, color: Color) {
                        let resolved = context.resolve(
                            Text("\(value)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(color.opacity(0.8))
                        )
                        let y = min(max(position, rect.minY + 4), rect.maxY - 4)
                        context.draw(resolved, at: CGPoint(x: 2, y: y), anchor: .leading)
                    }
                    func thresholdLine(_ value: Int, color: Color) {
                        var line = Path()
                        line.move(to: CGPoint(x: rect.minX, y: y(Double(value))))
                        line.addLine(to: CGPoint(x: rect.maxX, y: y(Double(value))))
                        context.stroke(line, with: .color(color.opacity(0.45)),
                                       style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        thresholdLabel(value, at: y(Double(value)), color: color)
                    }

                    // The target band, then its ends labelled on the axis.
                    let band = Path(CGRect(x: rect.minX, y: y(Double(targets.high)), width: rect.width,
                                           height: max(1, y(Double(targets.low)) - y(Double(targets.high)))))
                    context.fill(band, with: .color(.green.opacity(0.07)))
                    thresholdLine(targets.high, color: .yellow)
                    thresholdLine(targets.low, color: .red)

                    // Each segment wears the color of the reading it reaches,
                    // so the line shows when it left the target range.
                    for index in 1..<points.count {
                        let start = CGPoint(x: x(points[index - 1].date), y: y(points[index - 1].value))
                        let end = CGPoint(x: x(points[index].date), y: y(points[index].value))
                        var segment = Path()
                        segment.move(to: start)
                        segment.addLine(to: end)
                        let level = points[index].level
                        context.stroke(segment, with: .color(GlucoseText.color(for: level)),
                                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                    if let last = points.last {
                        let dot = CGRect(x: x(last.date) - 2.5, y: y(last.value) - 2.5, width: 5, height: 5)
                        context.fill(Path(ellipseIn: dot),
                                     with: .color(GlucoseText.color(for: last.level)))
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(readings.first.map { "\($0.displayText) \(unit)" } ?? "")
    }

    /// Oldest first, one point per sensor time, at most a day.
    private var plotted: [(date: Date, value: Double, level: GlucoseLevel)] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return readings
            .filter { $0.recordedAt >= cutoff }
            .sorted { $0.recordedAt < $1.recordedAt }
            .compactMap { reading in
                reading.chartValue.map {
                    (reading.recordedAt, $0, targets.level(for: reading))
                }
            }
    }
}
