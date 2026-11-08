// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A Dexcom reading in the closed island beside a camera: the drop on the
/// left and the value with its direction on the right. LOW and HIGH keep
/// their words rather than becoming numbers outside the measuring range.
struct NotchGlucoseStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var glucose = GlucoseService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchGlucoseLowThreshold) private var lowThreshold = GlucoseTargets.defaultLow
    @AppStorage(DefaultsKey.notchGlucoseHighThreshold) private var highThreshold = GlucoseTargets.defaultHigh

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconSize: CGFloat { NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight) }
    private var wing: CGFloat { geometry.compactActivityWingWidth }
    private var textInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) }
    private var reading: GlucoseReading? { glucose.reading }
    private var targets: GlucoseTargets { GlucoseTargets(low: lowThreshold, high: highThreshold) }
    private var tint: Color { GlucoseText.tint(reading, targets: targets) }

    var body: some View {
        Button { service.openActivity(.glucose) } label: {
            HStack(spacing: 0) {
                Image(systemName: NotchModule.glucose.symbol)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: wing, alignment: .center)
                    .opacity(wing >= 28 ? 1 : 0)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                HStack(spacing: NotchCapsuleLayout.markSpacing) {
                    Text(reading?.displayText ?? "--")
                        .font(.system(size: textSize, weight: .semibold)).monospacedDigit()
                    if let symbol = reading?.trend?.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: textSize * 0.9, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.trailing, textInset)
                .frame(width: wing, alignment: .trailing)
                .clipped()
            }
            .frame(height: geometry.compactActivityContentHeight)
            .padding(.horizontal, geometry.compactActivityHorizontalPadding)
            .padding(.top, geometry.compactActivityTopPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FeatureStrings.notchGlucose(l10n.language).title)
        .accessibilityValue(GlucoseText.accessibility(reading, targets: targets, language: l10n.language))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityIdentifier("notch.glucose")
    }
}

/// The reading's color and the words VoiceOver and the page use.
enum GlucoseText {
    static func color(for level: GlucoseLevel) -> Color {
        switch level {
        case .low: return .red
        case .inRange: return .green
        case .high: return .yellow
        }
    }

    static func tint(_ reading: GlucoseReading?, targets: GlucoseTargets) -> Color {
        guard let reading else { return .white }
        return color(for: targets.level(for: reading))
    }

    static func age(_ date: Date, now: Date = Date(), language: AppLanguage) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func accessibility(_ reading: GlucoseReading?, targets: GlucoseTargets,
                             language: AppLanguage) -> String {
        let text = FeatureStrings.notchGlucose(language)
        guard let reading else { return text.noReading }
        let direction = reading.trend?.spoken ?? "steady"
        let age = age(reading.recordedAt, language: language)
        let shown = reading.status == nil ? "\(reading.displayText) \(text.unit)" : reading.displayText
        let range: String
        switch targets.level(for: reading) {
        case .low: range = "below target"
        case .inRange: range = "in target"
        case .high: range = "above target"
        }
        return "\(shown), \(direction), \(range), \(text.updated(age))"
    }
}
