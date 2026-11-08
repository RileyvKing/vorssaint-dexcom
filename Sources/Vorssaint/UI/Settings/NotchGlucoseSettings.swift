// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Glucose section's options: the Dexcom Share sign-in, a one-shot test,
/// and whether a fresh reading takes the closed island.
struct NotchGlucoseSettingsControls: View {
    @Binding var priority: Bool

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchGlucoseEnabled) private var enabled = true
    @AppStorage(DefaultsKey.notchGlucoseRegion) private var regionRaw = GlucoseRegion.us.rawValue
    @AppStorage(DefaultsKey.notchGlucoseLowThreshold) private var lowThreshold = GlucoseTargets.defaultLow
    @AppStorage(DefaultsKey.notchGlucoseHighThreshold) private var highThreshold = GlucoseTargets.defaultHigh

    @State private var username = ""
    @State private var password = ""
    @State private var testing = false
    @State private var status: Status?
    @State private var loaded = false

    private var text: NotchGlucoseStrings { FeatureStrings.notchGlucose(l10n.language) }
    private var region: GlucoseRegion { GlucoseRegion.stored(regionRaw) }
    private var canTest: Bool {
        !testing && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
    private var statusSymbol: String {
        switch status {
        case .success, .saved: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case nil: return "circle"
        }
    }

    private enum Status: Equatable {
        case success(String)
        case failure(String)
        case saved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.showInIsland, isOn: $enabled)
                .disabled(!AppFeature.notchGlucose.isAvailable)
            Text(text.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            Text(text.account).font(.subheadline.weight(.medium))
            Text(text.accountHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(text.username, text: $username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
                .accessibilityLabel(text.username)
            SecureField(text.password, text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .accessibilityLabel(text.password)

            SettingsRow(symbol: "globe", title: text.region) {
                Picker(text.region, selection: $regionRaw) {
                    Text(text.regionUS).tag(GlucoseRegion.us.rawValue)
                    Text(text.regionOUS).tag(GlucoseRegion.ous.rawValue)
                    Text(text.regionJP).tag(GlucoseRegion.jp.rawValue)
                }
                .labelsHidden()
            }

            HStack(spacing: 8) {
                Button(testing ? text.testing : text.saveAndTest) { test() }
                    .disabled(!canTest)
                Button(text.clear, role: .destructive, action: clear)
                    .disabled(username.isEmpty && password.isEmpty)
                if testing { ProgressView().controlSize(.small) }
            }

            if let status {
                Label {
                    Text(message(for: status))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: statusSymbol)
                }
                .font(.caption)
                .foregroundStyle(statusColor)
            }

            Divider()
            Toggle(text.priority, isOn: $priority)
            Text(text.priorityHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            Text(text.targetRange).font(.subheadline.weight(.medium))
            Text(text.targetRangeHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsRow(symbol: "arrow.down.to.line", title: text.lowThreshold) {
                HStack(spacing: 5) {
                    TextField("", value: $lowThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .accessibilityLabel(text.lowThreshold)
                    Text(text.unit).font(.caption).foregroundStyle(.secondary)
                    Stepper("", value: $lowThreshold,
                            in: GlucoseTargets.range.lowerBound...max(GlucoseTargets.range.lowerBound + 1, highThreshold - 1))
                        .labelsHidden()
                        .accessibilityLabel(text.lowThreshold)
                }
            }
            SettingsRow(symbol: "arrow.up.to.line", title: text.highThreshold) {
                HStack(spacing: 5) {
                    TextField("", value: $highThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .accessibilityLabel(text.highThreshold)
                    Text(text.unit).font(.caption).foregroundStyle(.secondary)
                    Stepper("", value: $highThreshold,
                            in: min(GlucoseTargets.range.upperBound - 1, lowThreshold + 1)...GlucoseTargets.range.upperBound)
                        .labelsHidden()
                        .accessibilityLabel(text.highThreshold)
                }
            }

            Text(text.notMedical)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: load)
        .onChange(of: enabled) { NotchService.shared.syncWithPreferences() }
        .onChange(of: regionRaw) { GlucoseService.shared.credentialsChanged() }
        .onChange(of: lowThreshold) { _, value in
            let next = min(max(value, GlucoseTargets.range.lowerBound), GlucoseTargets.range.upperBound - 1)
            if next >= highThreshold { highThreshold = min(GlucoseTargets.range.upperBound, next + 1) }
            if next != lowThreshold { lowThreshold = next }
        }
        .onChange(of: highThreshold) { _, value in
            let next = min(max(value, GlucoseTargets.range.lowerBound + 1), GlucoseTargets.range.upperBound)
            if next <= lowThreshold { lowThreshold = max(GlucoseTargets.range.lowerBound, next - 1) }
            if next != highThreshold { highThreshold = next }
        }
    }

    private var statusColor: Color {
        switch status {
        case .failure: return .orange
        default: return .green
        }
    }

    private func message(for status: Status) -> String {
        switch status {
        case .success(let message), .failure(let message): return message
        case .saved: return text.credentialsSaved
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        username = GlucoseKeychain.string(.username) ?? ""
        password = GlucoseKeychain.string(.password) ?? ""
        if !username.isEmpty && !password.isEmpty { status = .saved }
        let low = min(max(lowThreshold, GlucoseTargets.range.lowerBound), GlucoseTargets.range.upperBound - 1)
        let high = min(max(highThreshold, low + 1), GlucoseTargets.range.upperBound)
        if low != lowThreshold { lowThreshold = low }
        if high != highThreshold { highThreshold = high }
    }

    private func test() {
        let enteredName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredPassword = password
        guard !enteredName.isEmpty, !enteredPassword.isEmpty else {
            status = .failure(text.credentialsMissing)
            return
        }
        testing = true
        status = nil
        let selectedRegion = region
        Task {
            let result = await GlucoseService.shared.testConnection(
                username: enteredName, password: enteredPassword, region: selectedRegion)
            await MainActor.run {
                testing = false
                switch result {
                case .success(let readings):
                    let savedName = GlucoseKeychain.set(enteredName, for: .username)
                    let savedPassword = GlucoseKeychain.set(enteredPassword, for: .password)
                    guard savedName && savedPassword else {
                        status = .failure(text.saveFailed)
                        return
                    }
                    if let latest = readings.first {
                        let age = GlucoseText.age(latest.recordedAt, language: l10n.language)
                        status = .success(text.signedIn(latest, age: age))
                    } else {
                        status = .success(text.testNoReadings)
                    }
                    GlucoseService.shared.credentialsChanged()
                case .failure(let error):
                    status = .failure(text.error(error))
                }
            }
        }
    }

    private func clear() {
        GlucoseKeychain.clear()
        username = ""
        password = ""
        status = nil
        GlucoseService.shared.credentialsChanged()
    }
}
