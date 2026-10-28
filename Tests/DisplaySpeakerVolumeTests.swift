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

        typealias Level = BrightnessSupport.WriteOnlySpeakerLevel
        let firstUse = Level.firstUse()
        suite.expect(firstUse.raw == 12 && firstUse.maximum == 100 && !firstUse.muted,
                     "a write-only monitor's speakers start at a low 12 of 100")
        suite.expect(BrightnessSupport.writeOnlySpeakerLevel(probesAudio: true, pathKey: "msi", optedInPaths: ["msi"],
                                                             storedLevels: nil) == firstUse
                     && BrightnessSupport.writeOnlySpeakerLevel(probesAudio: true, pathKey: "msi", optedInPaths: ["msi"],
                        storedLevels: ["msi": ["raw": 40, "max": 100, "muted": true]])
                        == Level(raw: 40, maximum: 100, muted: true),
                     "an opted-in write-only path gets speakers at its stored level, or the low first-use level")
        suite.expect(BrightnessSupport.writeOnlySpeakerLevel(probesAudio: true, pathKey: "msi", optedInPaths: [],
                        storedLevels: ["msi": ["raw": 40]]) == nil
                     && BrightnessSupport.writeOnlySpeakerLevel(probesAudio: false, pathKey: "msi", optedInPaths: ["msi"],
                        storedLevels: nil) == nil
                     && BrightnessSupport.writeOnlySpeakerLevel(probesAudio: true, pathKey: nil, optedInPaths: ["msi"],
                        storedLevels: nil) == nil,
                     "a write-only path gets no speakers without the opt-in, the speaker setting or a path")

        let outputs = [output(msiUID, "MPG321UX OLED"),
                       output("BuiltInSpeakerDevice", "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn,
                              settable: true)]
        suite.expect(BrightnessSupport.offersWriteOnlySpeakers(displayID: 3, outputs: outputs, displays: desk)
                     && !BrightnessSupport.offersWriteOnlySpeakers(displayID: 4, outputs: outputs, displays: desk)
                     && !BrightnessSupport.offersWriteOnlySpeakers(displayID: 3, outputs: [output(msiUID, settable: true)],
                                                                   displays: desk),
                     "the speaker opt-in is offered only for a display a fixed-volume display output matches")
        func choice(active: Bool = true, ddc: Bool = true, readable: Bool = false, path: String? = "msi",
                    wanted: Bool = true, optedIn: Set<String> = [], matches: Bool = true) -> Bool? {
            BrightnessSupport.writeOnlySpeakerChoice(isActive: active, isDDC: ddc, readable: readable, pathKey: path,
                                                     speakersWanted: wanted, optedInPaths: optedIn,
                                                     outputMatches: matches)
        }
        suite.expect(choice() == false && choice(optedIn: ["msi"]) == true
                     && choice(matches: false) == nil && choice(optedIn: ["msi"], matches: false) == true,
                     "the opt-in shows with evidence, and stays visible once chosen so it can be turned off")
        suite.expect(choice(active: false) == nil && choice(ddc: false) == nil && choice(readable: true) == nil
                     && choice(path: nil) == nil && choice(wanted: false) == nil
                     && choice(readable: true, optedIn: ["msi"]) == nil,
                     "readable, software-dimmed, inactive or pathless displays and a disabled speaker setting never offer it")

        var level = Level(raw: 12)
        suite.expect(level.standardStep == 6 && Level(raw: 0, maximum: 50).standardStep == 3
                     && Level(raw: 0, maximum: 8).standardStep == 1,
                     "a write-only key step is a sixteenth of the range, at least one unit")
        level.step(direction: 1, fine: false)
        let up = level.raw
        level.step(direction: 1, fine: true)
        let fineUp = level.raw
        level.step(direction: -1, fine: false)
        suite.expect(up == 18 && fineUp == 19 && level.raw == 13 && level.deviceValue == 13,
                     "write-only keys step the stored raw level by 6, or by 1 for the fine step")
        var low = Level(raw: 3)
        low.step(direction: -1, fine: false)
        var high = Level(raw: 98)
        high.step(direction: 1, fine: false)
        suite.expect(low.raw == 0 && high.raw == 100, "write-only steps stay between 0 and the maximum")

        var muted = Level(raw: 40)
        muted.toggleMute()
        suite.expect(muted.muted && muted.deviceValue == 0 && muted.raw == 40,
                     "a write-only mute writes level 0 and keeps the level to come back to")
        var unmuted = muted
        unmuted.toggleMute()
        suite.expect(!unmuted.muted && unmuted.deviceValue == 40, "unmuting writes the level from before the mute")
        var raised = muted
        raised.step(direction: 1, fine: false)
        var lowered = muted
        lowered.step(direction: -1, fine: false)
        suite.expect(!raised.muted && raised.deviceValue == 46 && !lowered.muted && lowered.deviceValue == 34,
                     "a volume key while muted unmutes from the level before the mute, one step up or down")

        var slider = muted
        slider.set(volume: 0.5, raises: true)
        var quiet = muted
        quiet.set(volume: 0.2, raises: false)
        var invalid = Level(raw: 40)
        invalid.set(volume: .nan, raises: true)
        suite.expect(slider.deviceValue == 50 && !slider.muted && quiet.muted && quiet.raw == 20 && invalid.raw == 40,
                     "a slider set unmutes at its level, a lower keeps a mute, and a non-number changes nothing")

        suite.expect(Level(stored: Level(raw: 33, muted: true).stored) == Level(raw: 33, muted: true)
                     && Level(stored: ["raw": 500, "max": 100]) == Level(raw: 100)
                     && Level(stored: ["raw": 5, "max": 0])?.maximum == 100
                     && Level(stored: ["max": 100]) == nil && Level(stored: "12") == nil,
                     "a stored write-only level reads back sanitized, and a malformed one reads as none")
        let storedLevels: [String: Any] = ["msi": ["raw": 30], "gone": ["raw": 70]]
        let kept = BrightnessSupport.updatedWriteOnlySpeakerLevels(storedLevels, path: "msi", level: Level(raw: 31),
                                                                   optedInPaths: ["msi"])
        suite.expect(Set(kept.keys) == ["msi"] && Level(stored: kept["msi"]) == Level(raw: 31)
                     && BrightnessSupport.updatedWriteOnlySpeakerLevels(storedLevels, path: "msi", level: nil,
                                                                        optedInPaths: ["msi"]).isEmpty
                     && BrightnessSupport.updatedWriteOnlySpeakerLevels([:], path: "samsung", level: Level(raw: 9),
                                                                        optedInPaths: ["msi"]).isEmpty,
                     "stored write-only levels keep only opted-in paths")
        suite.expect(BrightnessSupport.sendsWriteOnlyLevel(pathKey: "msi", readable: false, optedInPaths: ["msi"])
                     && !BrightnessSupport.sendsWriteOnlyLevel(pathKey: "msi", readable: false, optedInPaths: [])
                     && !BrightnessSupport.sendsWriteOnlyLevel(pathKey: "msi", readable: true, optedInPaths: ["msi"])
                     && !BrightnessSupport.sendsWriteOnlyLevel(pathKey: nil, readable: false, optedInPaths: ["msi"]),
                     "a queued write-only level is sent only while its path is still opted in and write-only")
        var afterRead = Level.read(volume: 0.1, maximum: 100)
        afterRead.step(direction: 1, fine: false)
        var wideRead = Level.read(volume: 0.5, maximum: 200)
        wideRead.step(direction: -1, fine: true)
        suite.expect(afterRead.deviceValue == 16 && wideRead.raw == 99 && wideRead.maximum == 200
                     && Level.read(volume: 0.1, maximum: 0) == Level(raw: 10),
                     "a level read while the monitor answered replaces the stored one, so a return to write-only steps from it")
        let merged = BrightnessSupport.mergedReadSpeakerLevels(
            ["msi": ["raw": 80], "samsung": ["raw": 30], "gone": ["raw": 50]],
            read: ["msi": Level(raw: 10), "optedOut": Level(raw: 70)], optedInPaths: ["msi", "samsung"])
        suite.expect(Set(merged.keys) == ["msi", "samsung"] && Level(stored: merged["msi"]) == Level(raw: 10)
                     && Level(stored: merged["samsung"]) == Level(raw: 30),
                     "levels read during a scan are stored only for paths still opted in when it publishes")
        suite.expect(BrightnessSupport.writeOnlySeedDisplays(paths: [3: "msi", 4: "samsung"], awaiting: ["msi"]) == [3]
                     && BrightnessSupport.writeOnlySeedDisplays(paths: [3: "msi", 4: "samsung"],
                                                                awaiting: ["samsung", "msi"]) == [3, 4]
                     && BrightnessSupport.writeOnlySeedDisplays(paths: [4: "samsung"], awaiting: ["msi"]).isEmpty
                     && BrightnessSupport.writeOnlySeedDisplays(paths: [:], awaiting: ["msi"]).isEmpty,
                     "turning the opt-in on sends the starting level once the monitor's speaker route exists")

        typealias KeyTarget = BrightnessSupport.VolumeKeyTarget
        typealias Claim = BrightnessSupport.VolumeKeyClaim
        let speakers: [UInt32: Bool] = [3: true, 4: false]
        let msiOutput = KeyTarget(displayID: 3, supportsMute: true)
        func claim(_ action: BrightnessSupport.VolumeKeyAction = .step(direction: 1), follows: Bool = true,
                   pointer: UInt32?, output: KeyTarget? = msiOutput) -> Claim? {
            BrightnessSupport.volumeKeyClaim(action, followsPointer: follows, pointerDisplay: pointer,
                                             speakerDisplays: speakers, outputTarget: output)
        }
        suite.expect(claim(pointer: 4) == Claim(displayID: 4, followsPointer: true)
                     && claim(pointer: 3) == Claim(displayID: 3, followsPointer: false),
                     "with the pointer setting on, a volume key reaches the speakers of the monitor under the pointer")
        suite.expect(claim(pointer: 1) == Claim(displayID: 3, followsPointer: false)
                     && claim(pointer: 9) == Claim(displayID: 3, followsPointer: false)
                     && claim(pointer: nil) == Claim(displayID: 3, followsPointer: false),
                     "the pointer on the built-in or on a monitor without speakers keeps the output's monitor")
        suite.expect(claim(.toggleMute, pointer: 4) == Claim(displayID: 3, followsPointer: false)
                     && claim(.toggleMute, pointer: 4, output: KeyTarget(displayID: 3, supportsMute: false)) == nil,
                     "a mute key under a monitor without mute falls back to the output, and to macOS without one")
        suite.expect(claim(follows: false, pointer: 4) == Claim(displayID: 3, followsPointer: false)
                     && claim(.toggleMute, follows: false, pointer: 3) == Claim(displayID: 3, followsPointer: false)
                     && claim(follows: false, pointer: 4, output: nil) == nil,
                     "with the pointer setting off, keys follow only the output whatever is under the pointer")
        suite.expect(claim(pointer: 1, output: nil) == nil && claim(pointer: nil, output: nil) == nil,
                     "with no speakers under the pointer and none on the output, the key stays with macOS")
        let airPods = output("AirPods-UID", "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth, settable: true)
        let builtInSpeakers = output("BuiltInSpeakerDevice", "MacBook Pro Speakers",
                                     transport: kAudioDeviceTransportTypeBuiltIn, settable: true)
        suite.expect(BrightnessSupport.pointerVolumeKeysActive(enabled: true, output: output(msiUID))
                     && !BrightnessSupport.pointerVolumeKeysActive(enabled: true, output: airPods)
                     && !BrightnessSupport.pointerVolumeKeysActive(enabled: true, output: builtInSpeakers)
                     && !BrightnessSupport.pointerVolumeKeysActive(enabled: true, output: output(msiUID, settable: true))
                     && !BrightnessSupport.pointerVolumeKeysActive(enabled: true, output: nil)
                     && !BrightnessSupport.pointerVolumeKeysActive(enabled: false, output: output(msiUID)),
                     "the pointer decides only while the sound leaves through a display output macOS cannot set")
        suite.expect(claim(follows: BrightnessSupport.pointerVolumeKeysActive(enabled: true, output: airPods),
                           pointer: 4, output: nil) == nil,
                     "with AirPods playing, a volume key over an opted-in monitor stays with macOS")
        typealias Hold = BrightnessSupport.VolumeKeyHold
        func hold(_ follows: Bool, pointerPath: [UInt32?], output: KeyTarget? = msiOutput) -> [Claim?] {
            var held: Hold?
            var claims: [Claim?] = []
            for (index, pointer) in pointerPath.enumerated() {
                let claim = BrightnessSupport.volumeKeyPressClaim(
                    .step(direction: 1), isRepeat: index > 0, held: held, followsPointer: follows,
                    pointerDisplay: pointer, speakerDisplays: speakers, outputTarget: output)
                if index == 0 {
                    held = claim.map { $0.followsPointer ? .pointer($0.displayID) : .output }
                }
                claims.append(claim)
            }
            return claims
        }
        let outputHold = hold(true, pointerPath: [1, 4, 4])
        suite.expect(outputHold == [Claim(displayID: 3, followsPointer: false), Claim(displayID: 3, followsPointer: false),
                                    Claim(displayID: 3, followsPointer: false)],
                     "a held key that went to the output's monitor keeps going there when the pointer moves onto speakers")
        let pointerHold = hold(true, pointerPath: [4, 3, 1])
        suite.expect(pointerHold == [Claim(displayID: 4, followsPointer: true), Claim(displayID: 4, followsPointer: true),
                                     Claim(displayID: 4, followsPointer: true)],
                     "a held key that went to the monitor under the pointer keeps going there wherever the pointer moves")
        suite.expect(hold(true, pointerPath: [1, 4], output: nil) == [nil, nil],
                     "a held key that went to macOS stays with macOS when the pointer moves onto speakers")
        suite.expect(hold(true, pointerPath: [4]) == [Claim(displayID: 4, followsPointer: true)]
                     && hold(true, pointerPath: [1]) == [Claim(displayID: 3, followsPointer: false)],
                     "after the key is released, the next press follows the pointer again")
        suite.expect(hold(false, pointerPath: [4, 4]) == [Claim(displayID: 3, followsPointer: false),
                                                          Claim(displayID: 3, followsPointer: false)]
                     && hold(false, pointerPath: [1, 1], output: nil) == [nil, nil],
                     "with the pointer setting off, held keys follow only the output as before")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.displayVolumeKeysFollowPointer] as? Bool == false
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.displayVolumeKeysFollowPointer),
                     "volume keys following the pointer is off until enabled and travels in a settings backup")
        suite.expect(AppLanguage.allCases.allSatisfy {
                         let strings = FeatureStrings.brightness($0)
                         return !strings.volumeKeysPointerToggle.isEmpty && !strings.volumeKeysPointerCaption.isEmpty
                             && ($0 == .enUS
                                 || strings.volumeKeysPointerToggle != FeatureStrings.brightness(.enUS).volumeKeysPointerToggle)
                     },
                     "the volume keys pointer setting is translated in every language")

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
        suite.expect([DefaultsKey.displayAudioBlindPaths, DefaultsKey.displayAudioLevels].allSatisfy {
                         SettingsBackupSupport.machineStateKeys.contains($0) && !SettingsBackupSupport.exportKeys().contains($0)
                     },
                     "a monitor's write-only speaker opt-in and level stay on this Mac")
        suite.expect(AppLanguage.allCases.allSatisfy {
                         let strings = FeatureStrings.brightness($0)
                         return !strings.writeOnlySpeakers.isEmpty && !strings.writeOnlySpeakersCaption.isEmpty
                             && !strings.speakersLabel.isEmpty && !strings.noMonitorSpeakers.isEmpty
                             && ($0 == .enUS || strings.speakersLabel != FeatureStrings.brightness(.enUS).speakersLabel)
                             && ($0 == .enUS || strings.writeOnlySpeakers != FeatureStrings.brightness(.enUS).writeOnlySpeakers)
                     },
                     "the write-only speaker opt-in is translated in every language")
    }
}
