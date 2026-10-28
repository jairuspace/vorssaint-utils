// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Panel section with one brightness slider per adjustable display. Values
/// refresh whenever the section appears, so changes made with the keyboard,
/// in System Settings or on the monitor itself are picked up.
struct BrightnessSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.brightnessOSDEnabled) private var brightnessOSDEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @State private var optionsExpanded = false
    var collapsible = true

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    var body: some View {
        PanelSection(.brightness, title: strings.pageTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                if service.displays.isEmpty {
                    Text(strings.noDisplays)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(service.displays) { display in
                        row(display)
                    }
                }
                if let failure = service.displayControlFailure {
                    Text(displayControlFailureText(failure, strings: strings))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
                if service.keyboardLightEnabled != nil {
                    Divider()
                    keyboardLightRow
                }
                if service.brightnessOSDSupported {
                    Divider()
                    Toggle(strings.osdToggle, isOn: $brightnessOSDEnabled)
                        .font(.system(size: 10.5, weight: .medium))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help(strings.osdCaption)
                        .onChange(of: brightnessOSDEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                }
                if AppFeature.extraBrightness.isAvailable {
                    Divider()
                    ExtraBrightnessPanelToggle()
                }
                Divider()
                optionsDisclosure
            }
            .panelCard()
            .onAppear {
                service.refresh()
                service.refreshKeyboardLight()
            }
        }
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(optionsExpanded ? 90 : 0))
                    Text(l10n.s.keepAwakeOptions)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(strings.keysToggle, isOn: $brightnessKeysEnabled)
                        .onChange(of: brightnessKeysEnabled) { _, isOn in
                            if isOn { permissions.requestAccessibility() }
                            service.syncWithPreferences()
                        }
                    Text(strings.keysCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if brightnessKeysEnabled, !permissions.accessibility {
                        Button {
                            permissions.openAccessibilitySettings()
                        } label: {
                            Label(l10n.s.permissionOpenSettings, systemImage: "hand.raised")
                        }
                        .buttonStyle(.link)
                    }
                    DisplayBrightnessShortcutControls()
                }
                .font(.system(size: 11.5, weight: .medium))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .padding(.leading, 19)
            }
        }
    }

    private func row(_ display: BrightnessDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(display.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if display.isActive, display.method != nil {
                    Text("\(Int((display.brightness * 100).rounded()))%")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if !display.isActive {
                    Text(strings.displayOff)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                DisplayPowerButton(display: display, compact: true)
            }
            if display.isActive, display.method != nil {
                Slider(value: brightnessBinding(display), in: 0...1)
                    .controlSize(.small)
                    .disabled(service.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
            }
            SoftwareDimmingButton(display: display, compact: true)
            if display.isActive, let audio = display.audio {
                volumeRow(display, audio: audio)
            } else if service.writeOnlySpeakerChoices[display.id] != nil {
                WriteOnlySpeakersOfferRow(display: display)
            }
        }
    }

    /// Sits with the display sliders because it is the same control. The
    /// Quick toggles switch stays the place to flip it off and back on, and
    /// the slider reaches 0, so the row carries no switch of its own.
    private var keyboardLightRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(strings.keyboardLight)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(((service.keyboardLightLevel ?? 0) * 100).rounded()))%")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: keyboardLightBinding, in: 0...1,
                   onEditingChanged: service.keyboardLightDragChanged)
                .controlSize(.small)
                .accessibilityLabel(strings.keyboardLight)
        }
    }

    private var keyboardLightBinding: Binding<Double> {
        Binding(get: { Double(service.keyboardLightLevel ?? 0) },
                set: { service.setKeyboardLightLevel(Float($0)) })
    }

    private func brightnessBinding(_ display: BrightnessDisplay) -> Binding<Double> {
        Binding(get: { display.brightness },
                set: { service.setBrightness($0, for: display.id,
                                             showOSD: brightnessOSDEnabled) })
    }

    private func volumeRow(_ display: BrightnessDisplay,
                           audio: BrightnessDisplay.Audio) -> some View {
        HStack(spacing: 6) {
            if let muted = audio.muted {
                Button {
                    service.setMuted(!muted, for: display.id)
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(muted ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(muted ? strings.unmute : strings.mute)
                .accessibilityLabel(muted ? strings.unmute : strings.mute)
            } else {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Slider(value: Binding(get: { audio.volume },
                                  set: { service.setVolume($0, for: display.id) }),
                   in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("\(display.name) \(strings.volumeLabel)")
            Text("\(Int((audio.volume * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            WriteOnlySpeakersSwitch(display: display, compact: true)
        }
    }
}

private struct ExtraBrightnessPanelToggle: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ExtraBrightnessService.shared
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var enabled = false

    var body: some View {
        Toggle(l10n.s.extraBrightnessName, isOn: $enabled)
            .font(.system(size: 10.5, weight: .medium))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!service.supported && !enabled)
            .help(service.supported ? l10n.s.extraBrightnessCaption : l10n.s.extraBrightnessUnsupported)
            .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
            .onAppear { service.syncWithPreferences() }
    }
}

/// Shared routing choice, on every surface that shows the display rows: the
/// slider is just as dead on the Energy page as in the panel, so the way out
/// has to be there too.
///
/// On readable DDC displays, the choice extends the slider below the panel's
/// hardware minimum and is offered in Settings. On write-only DDC paths, it
/// keeps the existing fallback to software control on both surfaces (issue
/// #1589). Either choice stays visible until cleared.
struct SoftwareDimmingButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var extendedChosen: Bool { service.extendedDimmingPreferred.contains(display.id) }
    private var softwareChosen: Bool { service.softwareDimmingPreferred.contains(display.id) }
    private var chosen: Bool { extendedChosen || softwareChosen }
    private var usesExtendedDimming: Bool {
        !softwareChosen && (extendedChosen || (display.method == .ddc && display.readable))
    }

    private var offered: Bool {
        guard display.isActive, !display.isBuiltIn, display.canChooseDimming else { return false }
        if chosen { return true }
        guard display.method == .ddc else { return false }
        // The panel keeps only the write-only way out; extra dimming is
        // offered in Settings and joins the panel once it is on.
        return !(compact && display.readable)
    }

    var body: some View {
        if offered {
            Button {
                if usesExtendedDimming {
                    service.setExtendedDimmingPreferred(!extendedChosen, for: display.id)
                } else {
                    service.setSoftwareDimmingPreferred(!softwareChosen, for: display.id)
                }
            } label: {
                HStack(spacing: compact ? 4 : 5) {
                    Image(systemName: chosen ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                    Text(usesExtendedDimming ? strings.extendedDimming : strings.softwareDimming)
                        .font(.system(size: compact ? 10 : 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.isDisplayPending(display.id))
            .accessibilityLabel("\(display.name): \(usesExtendedDimming ? strings.extendedDimming : strings.softwareDimming)")
        }
    }
}

/// Shared power affordance used by Settings and the menu bar panel. It stays
/// icon-only in the row, with a localized tooltip and accessibility label.
struct DisplayPowerButton: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var pending: Bool { service.isDisplayPending(display.id) }
    private var enabled: Bool { service.canToggleDisplay(display) }

    private var label: String {
        if !service.displaySwitchingAvailable { return strings.switchUnavailable }
        if display.isActive, !enabled { return strings.lastDisplayCaption }
        return display.isActive ? strings.turnOffDisplay : strings.turnOnDisplay
    }

    var body: some View {
        Group {
            if pending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: compact ? 16 : 20, height: 18)
                    .accessibilityLabel(label)
            } else {
                Button {
                    service.toggleDisplay(display)
                } label: {
                    Image(systemName: display.isActive ? "power" : "power.circle.fill")
                        .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                        .foregroundStyle(display.isActive ? AnyShapeStyle(.secondary)
                                                         : AnyShapeStyle(.green))
                        .frame(width: compact ? 16 : 20, height: 18)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .help(label)
                .accessibilityLabel(label)
            }
        }
    }
}

func displayControlFailureText(_ failure: BrightnessService.DisplayControlFailure,
                               strings: BrightnessFeatureStrings) -> String {
    switch failure {
    case .unavailable: return strings.switchUnavailable
    case .lastActive: return strings.lastDisplayCaption
    case .failed: return strings.switchFailed
    case .closedLid: return strings.openLidToEnable
    }
}

/// The write-only speaker opt-in as a switch, for every surface that lists a
/// monitor's speakers. It shows only for a write-only monitor offered the
/// opt-in: with evidence the monitor carries the Mac's sound, and while it
/// is on, so it can be turned off where it was turned on.
struct WriteOnlySpeakersSwitch: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    var compact = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    var body: some View {
        if let chosen = service.writeOnlySpeakerChoices[display.id] {
            Toggle(strings.writeOnlySpeakers, isOn: Binding(
                get: { chosen },
                set: { service.setWriteOnlySpeakersPreferred($0, for: display.id) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(compact ? .mini : .small)
                .disabled(service.isDisplayPending(display.id))
                .help(strings.writeOnlySpeakersCaption)
                .accessibilityLabel("\(display.name): \(strings.writeOnlySpeakers)")
        }
    }
}

/// The panel's speaker line for a write-only monitor offered the opt-in while
/// its speakers are not built yet: just the label and the switch, so the
/// switch's meaning is plain. Once on, the monitor's normal speaker line
/// takes over.
struct WriteOnlySpeakersOfferRow: View {
    @ObservedObject private var l10n = L10n.shared
    let display: BrightnessDisplay

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(strings.speakersLabel)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            WriteOnlySpeakersSwitch(display: display, compact: true)
        }
    }
}

/// The columns of the Settings speaker table: a name column as wide as the
/// longest monitor name, the flexible slider, one percentage column and a
/// trailing slot as wide as the widest row's controls, so every slider starts
/// and ends at the same place. The name column gives way, truncating in the
/// middle, only where it would leave the slider narrower than its minimum.
struct DisplayRowColumns: Equatable {
    static let iconWidth: CGFloat = 26
    static let muteWidth: CGFloat = 20
    static let percentWidth: CGFloat = 40
    static let sliderMinWidth: CGFloat = 80
    static let spacing: CGFloat = 10
    var nameWidth: CGFloat = 120
    var trailingWidth: CGFloat = 0

    /// The name column for a row of `rowWidth`: the longest name, unless that
    /// would squeeze the slider below its minimum next to `trailingWidth`.
    static func nameColumnWidth(longestName: CGFloat, rowWidth: CGFloat,
                                trailingWidth: CGFloat) -> CGFloat {
        guard longestName > 0 else { return 120 }
        guard rowWidth > 0 else { return longestName.rounded(.up) }
        let fixed = iconWidth + muteWidth + percentWidth + sliderMinWidth + trailingWidth + spacing * 5
        return max(60, min(longestName.rounded(.up), rowWidth - fixed))
    }
}

/// The widest of one measured column among the speaker table's rows.
private struct DisplayRowTrailingWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DisplayRowNameWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DisplayRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The Settings speaker table: one aligned row per monitor whose speakers
/// can be driven. It measures its own rows to size the shared columns.
struct DisplaySpeakersTable: View {
    let monitors: [BrightnessDisplay]
    @State private var columns = DisplayRowColumns()
    @State private var longestName: CGFloat = 0
    @State private var rowWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(monitors) { display in
                DisplaySpeakersRow(display: display, columns: columns)
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: DisplayRowWidthKey.self, value: proxy.size.width)
        })
        .onPreferenceChange(DisplayRowTrailingWidthKey.self) { width in
            if columns.trailingWidth != width {
                columns.trailingWidth = width
                fitNameColumn()
            }
        }
        .onPreferenceChange(DisplayRowNameWidthKey.self) { width in
            if longestName != width {
                longestName = width
                fitNameColumn()
            }
        }
        .onPreferenceChange(DisplayRowWidthKey.self) { width in
            if rowWidth != width {
                rowWidth = width
                fitNameColumn()
            }
        }
    }

    private func fitNameColumn() {
        let width = DisplayRowColumns.nameColumnWidth(longestName: longestName, rowWidth: rowWidth,
                                                      trailingWidth: columns.trailingWidth)
        if columns.nameWidth != width { columns.nameWidth = width }
    }
}

/// One row of the Settings speaker table, in the familiar volume order: the
/// monitor's tile and name, the speaker button that mutes, the slider and the
/// level, with a write-only monitor's opt-in switch alone at the end. While
/// that switch is off the row shows nothing else, so its meaning is plain.
struct DisplaySpeakersRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = BrightnessService.shared
    let display: BrightnessDisplay
    let columns: DisplayRowColumns

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var audio: BrightnessDisplay.Audio? { display.isActive ? display.audio : nil }

    var body: some View {
        HStack(spacing: DisplayRowColumns.spacing) {
            Image(systemName: "display")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(display.isActive ? Color.accentColor : Color.secondary)
                .frame(width: DisplayRowColumns.iconWidth, height: 26)
                .background((display.isActive ? Color.accentColor : Color.secondary).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(display.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: columns.nameWidth, alignment: .leading)
                .background(alignment: .leading) {
                    Text(display.name)
                        .lineLimit(1)
                        .fixedSize()
                        .hidden()
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: DisplayRowNameWidthKey.self, value: proxy.size.width)
                        })
                }
                .help(display.name)
            if let audio {
                muteButton(audio)
                Slider(value: Binding(get: { audio.volume },
                                      set: { service.setVolume($0, for: display.id) }),
                       in: 0...1)
                    .accessibilityLabel("\(display.name) \(strings.volumeLabel)")
                    .frame(minWidth: DisplayRowColumns.sliderMinWidth)
                Text("\(Int((audio.volume * 100).rounded()))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: DisplayRowColumns.percentWidth, alignment: .trailing)
            } else {
                Spacer()
            }
            HStack(spacing: 0) {
                WriteOnlySpeakersSwitch(display: display)
            }
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.preference(key: DisplayRowTrailingWidthKey.self, value: proxy.size.width)
            })
            .frame(minWidth: columns.trailingWidth, alignment: .trailing)
        }
    }

    /// The speaker button that mutes, or a plain speaker symbol when the
    /// monitor has no mute. Write-only speakers always offer it.
    @ViewBuilder
    private func muteButton(_ audio: BrightnessDisplay.Audio) -> some View {
        if let muted = audio.muted {
            Button {
                service.setMuted(!muted, for: display.id)
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muted ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .frame(width: DisplayRowColumns.muteWidth, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(muted ? strings.unmute : strings.mute)
            .accessibilityLabel(muted ? strings.unmute : strings.mute)
        } else {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: DisplayRowColumns.muteWidth, height: 18)
        }
    }
}
