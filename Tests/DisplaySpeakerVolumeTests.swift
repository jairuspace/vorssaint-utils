// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// Pure rules behind a monitor's own speaker volume: the DDC replies, the
/// volume and mute key parsing and routing, and the remembered-path cache.
enum DisplaySpeakerVolumeTests {
    static func run(_ suite: TestSuite) {
        suite.expect(BrightnessSupport.audioReply(current: 50, maximum: 100) == 0.5
                     && BrightnessSupport.audioReply(current: 100, maximum: 100) == 1,
                     "a volume reply is read against its own maximum")
        suite.expect(BrightnessSupport.audioReply(current: 5, maximum: 0) == nil,
                     "a volume reply without a maximum is never trusted")

        suite.expect(BrightnessSupport.muteReply(current: 1, maximum: 2) == true
                     && BrightnessSupport.muteReply(current: 2, maximum: 2) == false,
                     "only the two MCCS mute values read as muted or unmuted")
        suite.expect(BrightnessSupport.muteReply(current: 0, maximum: 2) == nil
                     && BrightnessSupport.muteReply(current: 3, maximum: 100) == nil
                     && BrightnessSupport.muteReply(current: 1, maximum: 1) == nil,
                     "any other mute value is not a mute control")
        suite.expect(BrightnessSupport.muteDeviceValue(true) == BrightnessSupport.audioMutedValue
                     && BrightnessSupport.muteDeviceValue(false) == BrightnessSupport.audioUnmutedValue,
                     "mute writes use the MCCS values")

        suite.expect(BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeHDMI)
                     && BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeDisplayPort)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBuiltIn)
                     && !BrightnessSupport.isDisplayAudioTransport(kAudioDeviceTransportTypeBluetooth),
                     "only HDMI and DisplayPort outputs can belong to a monitor")
        suite.expect(BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: false)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeHDMI, outputHasSettableVolume: true)
                     && !BrightnessSupport.displayOwnsOutputVolume(
                        transport: kAudioDeviceTransportTypeBuiltIn, outputHasSettableVolume: false),
                     "keys reach a monitor only when its output cannot take macOS volume")
        typealias Mute = BrightnessSupport
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: false, to: 0, raises: false) == true
                     && Mute.monitorMuteChange(from: 0, muted: true, to: 0, raises: false) == nil,
                     "reaching zero mutes a monitor once, as macOS does for its own outputs")
        suite.expect(Mute.monitorMuteChange(from: 0, muted: false, to: 0.0625, raises: true) == false,
                     "leaving zero unmutes even when the last reading said unmuted, for monitors that mute themselves")
        suite.expect(Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.5, raises: true) == false
                     && Mute.monitorMuteChange(from: 0.4, muted: true, to: 0.3, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0.4, muted: false, to: 0.5, raises: true) == nil,
                     "a raise lifts a chosen mute, a lower leaves it, and an audible step writes no mute")
        suite.expect(Mute.monitorMuteChange(from: 0.0625, muted: nil, to: 0, raises: false) == nil
                     && Mute.monitorMuteChange(from: 0, muted: nil, to: 0.0625, raises: true) == nil,
                     "a monitor without an MCCS mute control never gets a mute write")
        suite.expect(Mute.unmutesAfterLevel(muted: false, volume: 0.01)
                     && !Mute.unmutesAfterLevel(muted: true, volume: 0)
                     && !Mute.unmutesAfterLevel(muted: false, volume: nil)
                     && !Mute.unmutesAfterLevel(muted: false, volume: 0)
                     && !Mute.unmutesAfterLevel(muted: nil, volume: 0.5),
                     "an unmute that leaves zero follows the level write, since monitors refuse it at zero")

        let msiUID = "3669D23D-0000-0000-0422-0104B5462778"
        let samsungUID = "4C2D0C75-0000-0000-0723-0104B5462878_0C80B000"
        suite.expect(BrightnessSupport.displayAudioIdentity(uid: msiUID).map { [$0.vendor, $0.model] } == [0x3669, 0x3DD2]
                     && BrightnessSupport.displayAudioIdentity(uid: samsungUID).map { [$0.vendor, $0.model] } == [0x4C2D, 0x750C],
                     "a display audio UID carries the EDID vendor big-endian and the product little-endian")
        suite.expect(BrightnessSupport.displayAudioIdentity(uid: "BuiltInSpeakerDevice") == nil
                     && BrightnessSupport.displayAudioIdentity(uid: "3669D23") == nil
                     && BrightnessSupport.displayAudioIdentity(uid: "3669D23DX") == nil
                     && BrightnessSupport.displayAudioIdentity(uid: "0000D23D-0000") == nil
                     && BrightnessSupport.displayAudioIdentity(uid: "") == nil,
                     "a UID without the EDID prefix gives no display identity")

        typealias Output = BrightnessSupport.AudioOutputDevice
        typealias Candidate = BrightnessSupport.DisplayAudioCandidate
        func output(_ uid: String, _ name: String = "", transport: UInt32 = kAudioDeviceTransportTypeDisplayPort,
                    settable: Bool = false) -> Output {
            Output(uid: uid, name: name, transport: transport, hasSettableVolume: settable, isDefault: true)
        }
        let desk = [Candidate(id: 1, name: "Built-in Retina Display", vendor: 0x610, model: 0xA050),
                    Candidate(id: 3, name: "MPG321UX OLED", vendor: 0x3669, model: 0x3DD2),
                    Candidate(id: 4, name: "Odyssey G5", vendor: 0x4C2D, model: 0x750C)]
        suite.expect(BrightnessSupport.displayForAudioOutput(output(samsungUID), displays: desk) == 4
                     && BrightnessSupport.displayForAudioOutput(output(msiUID), displays: desk) == 3,
                     "the sound device is matched to its display by the EDID identity in its UID")
        suite.expect(BrightnessSupport.displayForAudioOutput(output(msiUID, transport: kAudioDeviceTransportTypeBuiltIn),
                                                             displays: desk) == nil
                     && BrightnessSupport.displayForAudioOutput(output("BuiltInSpeakerDevice", "MacBook Pro Speakers",
                                                                       transport: kAudioDeviceTransportTypeBuiltIn),
                                                                displays: desk) == nil
                     && BrightnessSupport.displayForAudioOutput(output("iPhone-continuity-output", "iPhone",
                                                                       transport: kAudioDeviceTransportTypeContinuityCaptureWireless),
                                                                displays: desk) == nil,
                     "built-in speakers and an iPhone never route keys to a display, whatever their UID")
        suite.expect(BrightnessSupport.displayForAudioOutput(output(msiUID, settable: true), displays: desk) == nil,
                     "an output macOS can set the volume of never routes keys to a display")
        let twins = [Candidate(id: 5, name: "DELL U2720Q", vendor: 0x10AC, model: 0xA0C4),
                     Candidate(id: 6, name: "DELL U2720Q (2)", vendor: 0x10AC, model: 0xA0C4)]
        suite.expect(BrightnessSupport.displayForAudioOutput(output("10ACC4A0-0000-0000", "DELL U2720Q (2)"),
                                                             displays: twins) == 6
                     && BrightnessSupport.displayForAudioOutput(output("10ACC4A0-0000-0000", "dell u2720q"),
                                                                displays: twins) == 5,
                     "two monitors of the same model are told apart by the exact name, ignoring case")
        suite.expect(BrightnessSupport.displayForAudioOutput(output("10ACC4A0-0000-0000", "DELL U2720Q Audio"),
                                                             displays: twins) == nil
                     && BrightnessSupport.displayForAudioOutput(output("10ACC4A0-0000-0000"), displays: twins) == nil,
                     "two monitors of the same model with no exact name stay with macOS")
        suite.expect(BrightnessSupport.displayForAudioOutput(output("1E6D0777-0000-0000"), displays: desk) == nil,
                     "a display UID that matches no connected display routes nowhere")
        let named = [Candidate(id: 2, name: "LG HDR 4K", vendor: 0, model: 0),
                     Candidate(id: 3, name: "DELL U2720Q", vendor: 0, model: 0)]
        suite.expect(BrightnessSupport.displayForAudioOutput(output("hdmi-out", "dell u2720q"), displays: named) == 3,
                     "without a display UID the device is matched by its exact name, ignoring case")
        suite.expect(BrightnessSupport.displayForAudioOutput(output("hdmi-out", "LG"), displays: named) == nil
                     && BrightnessSupport.displayForAudioOutput(output("hdmi-out", "LG HDR 4K Audio"), displays: named) == nil
                     && BrightnessSupport.displayForAudioOutput(output("hdmi-out", ""), displays: named) == nil,
                     "a partial or missing name never matches a display")
        let sameName = [Candidate(id: 2, name: "LG HDR 4K", vendor: 0, model: 0),
                        Candidate(id: 3, name: "LG HDR 4K", vendor: 0, model: 0)]
        suite.expect(BrightnessSupport.displayForAudioOutput(output("hdmi-out", "LG HDR 4K"), displays: sameName) == nil,
                     "a name shared by two displays is ambiguous and stays with macOS")
        let lone = [Candidate(id: 7, name: "Studio Display", vendor: 0, model: 0)]
        suite.expect(BrightnessSupport.displayForAudioOutput(output("hdmi-out", "Display Audio"), displays: lone) == 7
                     && BrightnessSupport.displayForAudioOutput(output("hdmi-out", "Display Audio"), displays: named) == nil,
                     "without a display UID a lone display answers only while it is the only one active")
        suite.expect(MixerRoutingSupport.observationNeeds(isAvailable: { _ in false }, monitorSpeakers: true) == (true, false)
                     && MixerRoutingSupport.observationNeeds(isAvailable: { _ in false }) == (false, false),
                     "monitor speakers watch the output devices without starting per-app mixer taps")

        func keyData(_ code: Int, state: Int, repeatBit: Int = 0) -> Int {
            (code << 16) | (state << 8) | repeatBit
        }
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: 1),
                                                            isKeyDown: true, isRepeat: false),
                     "the volume-up key press parses as one step up")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(1, state: 11))
                        == BrightnessSupport.VolumeKeyEvent(action: .step(direction: -1),
                                                            isKeyDown: false, isRepeat: false),
                     "the volume-down key release parses as one step down")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(7, state: 10))
                        == BrightnessSupport.VolumeKeyEvent(action: .toggleMute,
                                                            isKeyDown: true, isRepeat: false),
                     "the mute key press parses as a mute toggle")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8,
                        data1: keyData(0, state: 10, repeatBit: 1))?.isRepeat == true,
                     "a held volume key is marked as a repeat")
        suite.expect(BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(2, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 7, data1: keyData(0, state: 10)) == nil
                     && BrightnessSupport.volumeKeyEvent(subtype: 8, data1: keyData(0, state: 7)) == nil,
                     "brightness keys, other subtypes and other states are never volume keys")

        suite.expect(BrightnessSupport.volumeKeyDelta(direction: 1, fine: false) == 1.0 / 16.0
                     && BrightnessSupport.volumeKeyDelta(direction: -1, fine: true) == -1.0 / 100.0,
                     "a plain key moves a sixteenth and Option+Shift a percent, in the key's direction")
        suite.expect(BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: false) == true
                     && BrightnessSupport.volumeKeyFineness(option: false, shift: false,
                        commandOrControl: false) == false
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: false,
                        commandOrControl: false) == nil
                     && BrightnessSupport.volumeKeyFineness(option: true, shift: true,
                        commandOrControl: true) == nil,
                     "Option+Shift is the fine step, Option alone and Command or Control stay with macOS")
        suite.expect(BrightnessSupport.steppedLevel(0.95, delta: 0.1) == 1
                     && BrightnessSupport.steppedLevel(0.05, delta: -0.1) == 0
                     && BrightnessSupport.steppedLevel(0.5, delta: 0.25) == 0.75,
                     "a volume step stays between silent and full")

        suite.expect(BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "c",
                        remembered: true, limit: 2) == ["b", "c"]
                     && BrightnessSupport.updatedRememberedPaths(["a", "b"], path: "a",
                        remembered: false) == ["b"],
                     "a silent-speaker path is remembered newest and forgotten when it changes")
        suite.expect(!BrightnessSupport.shouldProbe(pathKey: "a", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: "b", rememberedPaths: ["a"])
                     && BrightnessSupport.shouldProbe(pathKey: nil, rememberedPaths: ["a"]),
                     "a remembered silent path is not probed again, and an unknown path always is")
        suite.expect(BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: [])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: true, recheckedPaths: ["a"])
                     && !BrightnessSupport.shouldProbeLuminance(pathKey: "a", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: "b", writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: [])
                     && BrightnessSupport.shouldProbeLuminance(pathKey: nil, writeOnlyPaths: ["a"],
                        probesAudio: false, recheckedPaths: []),
                     "a remembered write-only path is read again once while speakers are wanted, then trusted")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: true) == 2
                     && BrightnessSupport.ddcRetryDelay(attempt: 2, probesAudio: true, repliedThisSession: true) == 5
                     && BrightnessSupport.ddcRetryDelay(attempt: 3, probesAudio: true, repliedThisSession: true) == 15,
                     "a monitor that answered before is read again after about 2, 5 and 15 seconds")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 4, probesAudio: true, repliedThisSession: true) == nil,
                     "the write-only answer stands once the third retry fails")
        suite.expect(BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: false, repliedThisSession: true) == nil
                     && BrightnessSupport.ddcRetryDelay(attempt: 1, probesAudio: true, repliedThisSession: false) == nil,
                     "a failed read is retried only while speakers are wanted and the monitor answered this session")
        suite.expect(BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: true, displayOwnsOutput: true,
                        now: 100, lastRescan: nil)
                     && !BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: false,
                        now: 100, lastRescan: nil),
                     "an unclaimed volume key rescans only while a monitor output has no target")
        suite.expect(!BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 109, lastRescan: 100)
                     && BrightnessSupport.rescansForVolumeKey(hasTarget: false, displayOwnsOutput: true,
                        now: 110, lastRescan: 100),
                     "volume keys rescan at most once every 10 seconds")
        suite.expect(BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: nil)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: false, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: true, scanned: true, queued: nil)
                     && BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: true)
                     && !BrightnessSupport.needsAudioScan(wanted: false, scanned: true, queued: false),
                     "a speaker scan is forced once per setting change, not again while one is queued")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.displayVolumeEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.displayVolumeKeysEnabled] as? Bool == false,
                     "speaker volume and its volume keys are off until enabled")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeEnabled)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeKeysEnabled),
                     "the speaker volume switches travel in a settings backup")
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.displayAudioSilentPaths)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayAudioSilentPaths),
                     "a monitor's silent-speaker memory stays on this Mac")
    }
}
