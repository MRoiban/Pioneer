//
//  SettingsModel.swift
//  Moonlight SwiftUI
//
//  Created by Michael Kenny on 25/1/2023.
//  Copyright © 2023 Moonlight Game Streaming Project. All rights reserved.
//

import AppKit
import Network
import SwiftUI

struct Host: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
}

class SettingsModel: ObservableObject {
    static var hosts: [Host?]? = {
        let dataMan = DataManager()
        if let tempHosts = dataMan.getHosts() as? [TemporaryHost] {
            let hosts = tempHosts.map { host in
                Host(
                    id: host.uuid,
                    name: host.name,
                    address: calibrationAddress(for: host)
                )
            }
            
            return hosts
        }
        
        
        return nil
    }()
    
    @Published var selectedHost: Host? {
        didSet {
            if selectedHost != nil {
                UserDefaults.standard.set(selectedHost?.id, forKey: "selectedSettingsProfile")
                loadSettings()
            }
        }
    }

    var resolutionChangedCallback: (() -> Void)?
    var fpsChangedCallback: (() -> Void)?

    @Published var selectedResolution: CGSize {
        didSet {
            saveSettings()
            resolutionChangedCallback?()
        }
    }
    @Published var selectedFps: Int {
        didSet {
            saveSettings()
            fpsChangedCallback?()
        }
    }
    @Published var customFps: CGFloat? {
        didSet {
            saveSettings()
        }
    }
    @Published var customResWidth: CGFloat? {
        didSet {
            saveSettings()
        }
    }
    @Published var customResHeight: CGFloat? {
        didSet {
            saveSettings()
        }
    }
    @Published var bitrateSliderValue: Float {
        didSet {
            saveSettings()
        }
    }
    @Published var isCalibratingBitrate = false
    @Published var bitrateCalibrationProgress: Double = 0
    @Published var bitrateCalibrationStatus: String?
    @Published var selectedVideoCodec: String {
        didSet {
            saveSettings()
        }
    }
    @Published var hdr: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedPacingOptions: String {
        didSet {
            saveSettings()
        }
    }
    @Published var audioOnPC: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var disableAWDLDuringStream: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var volumeLevel: CGFloat {
        didSet {
            saveSettings()
            NotificationCenter.default.post(name: Notification.Name("volumeSettingChanged"), object: nil)
        }
    }
    @Published var selectedMultiControllerMode: String {
        didSet {
            saveSettings()
        }
    }
    @Published var swapButtons: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var optimize: Bool {
        didSet {
            saveSettings()
        }
    }
    
    @Published var autoFullscreen: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var rumble: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedControllerDriver: String {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedMouseDriver: String {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseMode: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedParsecMouseShortcut: String {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseShortcutKeyCode: Int {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseShortcutModifierMask: UInt {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseShortcutDisplay: String {
        didSet {
            saveSettings()
        }
    }
    @Published var streamExitShortcutKeyCode: Int {
        didSet {
            saveSettings()
        }
    }
    @Published var streamExitShortcutModifierMask: UInt {
        didSet {
            saveSettings()
        }
    }
    @Published var streamExitShortcutDisplay: String {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseClientAuthoritativeCursor: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseEventDrivenPosition: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseIdleHostCorrection: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var parsecMouseDeltaAccumulatedVisibleCursor: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var audioDiagnosticsEnabled: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var lowLatencyMousePipeline: Bool {
        didSet {
            saveSettings()
        }
    }

    @Published var emulateGuide: Bool {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedWindowsCtrlSource: String {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedWindowsShiftSource: String {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedWindowsAltSource: String {
        didSet {
            saveSettings()
        }
    }
    @Published var selectedWindowsWinSource: String {
        didSet {
            saveSettings()
        }
    }
    @Published var appArtworkWidth: CGFloat? {
        didSet {
            saveSettings()
        }
    }
    @Published var appArtworkHeight: CGFloat? {
        didSet {
            saveSettings()
        }
    }
    @Published var dimNonHoveredArtwork: Bool {
        didSet {
            saveSettings()
        }
    }

    static var resolutions: [CGSize] {
        buildResolutionOptions().map(\.size)
    }
    static var fpss: [Int] = [30, 60, 90, 120, 144, .zero]
    static var bitrateSteps: [Float] = [
        0.5,
        1,
        1.5,
        2,
        2.5,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        12,
        15,
        18,
        20,
        25,
        30,
        40,
        50,
        60,
        70,
        80,
        90,
        100,
        120,
        150
    ]
    static var videoCodecs: [String] = ["H.264", "H.265"]
    static let pacingAuto = "Auto"
    static let pacingLowestLatency = "Lowest Latency"
    static let pacingBalanced = "Balanced"
    static let pacingSmoothest = "Smoothest"
    static var pacingOptions: [String] = [pacingAuto, pacingLowestLatency, pacingBalanced, pacingSmoothest]
    static var multiControllerModes: [String] = ["Single", "Auto"]

    static var controllerDrivers: [String] = ["HID", "MFi"]
    static var mouseDrivers: [String] = ["HID", "MFi", "Raw HID"]
    static var keyboardModifierSources: [String] = ["Control", "Shift", "Option", "Command", "Fn"]
    static var parsecMouseShortcutOptions: [String] = [
        "Control + Option + M",
        "Control + Option + P",
        "Control + Option + R",
        "Control + Option + Space",
        "Control + Option + Command + M"
    ]
    static var parsecMouseShortcutKeyCodes: [Int] = [46, 35, 15, 49, 46]
    static var parsecMouseShortcutModifierMasks: [UInt] = [
        NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue,
        NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue,
        NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue,
        NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue,
        NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.command.rawValue
    ]

    static let defaultResolution = CGSizeMake(1920, 1080)
    static let defaultCustomResWidth: CGFloat? = nil
    static let defaultCustomResHeight: CGFloat? = nil
    static let defaultFps = 60
    static let defaultCustomFps: CGFloat? = nil
    static let defaultBitrateSliderValue = {
        var bitrateIndex = 0
        for i in 0..<SettingsModel.bitrateSteps.count {
            if 10000.0 <= SettingsModel.bitrateSteps[i] * 1000.0 {
                bitrateIndex = i
                break
            }
        }
        return Float(bitrateIndex)
    }()
    static let defaultVideoCodec = "H.264"
    static let defaultHdr = false
    static let defaultPacingOptions = pacingAuto
    static let defaultAudioOnPC = false
    static let defaultDisableAWDLDuringStream = false
    static let defaultVolumeLevel = 1.0
    static let defaultMultiControllerMode = "Auto"
    static let defaultSwapButtons = false
    static let defaultOptimize = false
    static let defaultAutoFullscreen = true
    static let defaultRumble = true
    static let defaultControllerDriver = "HID"
    static let defaultMouseDriver = "HID"
    static let defaultParsecMouseMode = false
    static let defaultParsecMouseShortcut = "Control + Option + M"
    static let defaultParsecMouseShortcutKeyCode = 46
    static let defaultParsecMouseShortcutModifierMask = NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue
    static var defaultParsecMouseShortcutIndex: Int {
        getInt(from: defaultParsecMouseShortcut, in: parsecMouseShortcutOptions)
    }
    static let defaultStreamExitShortcut = "Command + Q"
    static let defaultStreamExitShortcutKeyCode = 12
    static let defaultStreamExitShortcutModifierMask = NSEvent.ModifierFlags.command.rawValue
    static let defaultParsecMouseClientAuthoritativeCursor = true
    static let defaultParsecMouseEventDrivenPosition = true
    static let defaultParsecMouseIdleHostCorrection = true
    static let defaultParsecMouseDeltaAccumulatedVisibleCursor = true
    static let defaultAudioDiagnosticsEnabled = false
    static let defaultLowLatencyMousePipeline = true
    static let defaultEmulateGuide = false
    static let defaultWindowsCtrlSource = "Control"
    static let defaultWindowsShiftSource = "Shift"
    static let defaultWindowsAltSource = "Option"
    static let defaultWindowsWinSource = "Command"
    static var defaultWindowsCtrlSourceIndex: Int {
        getInt(from: defaultWindowsCtrlSource, in: keyboardModifierSources)
    }
    static var defaultWindowsShiftSourceIndex: Int {
        getInt(from: defaultWindowsShiftSource, in: keyboardModifierSources)
    }
    static var defaultWindowsAltSourceIndex: Int {
        getInt(from: defaultWindowsAltSource, in: keyboardModifierSources)
    }
    static var defaultWindowsWinSourceIndex: Int {
        getInt(from: defaultWindowsWinSource, in: keyboardModifierSources)
    }
    static let defaultAppArtworkWidth: CGFloat? = nil
    static let defaultAppArtworkHeight: CGFloat? = nil
    static let defaultDimNonHoveredArtwork = true

    static func label(for resolution: CGSize) -> String {
        if resolution == .zero {
            return "Custom"
        }

        if let option = buildResolutionOptions().first(where: { $0.size == resolution }) {
            return option.label
        }

        return resolutionLabel(for: resolution)
    }

    func calibrateBitrate(duration: TimeInterval = 30) {
        guard !isCalibratingBitrate else {
            return
        }

        guard let selectedHost, !selectedHost.address.isEmpty else {
            bitrateCalibrationStatus = "Select an online host first."
            return
        }

        isCalibratingBitrate = true
        bitrateCalibrationProgress = 0
        bitrateCalibrationStatus = "Calibrating link to \(selectedHost.name)..."

        let address = Self.currentCalibrationAddress(for: selectedHost) ?? selectedHost.address
        let resolution = effectiveResolution
        let fps = effectiveFps

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startedAt = Date()
            var probeResults: [TimeInterval?] = []
            var failures = 0
            var attempts = 0

            while Date().timeIntervalSince(startedAt) < duration {
                autoreleasepool {
                    attempts += 1

                    if let sample = Self.measureHostProbe(address: address) {
                        probeResults.append(sample)
                    } else {
                        probeResults.append(nil)
                        failures += 1
                    }

                    let progress = min(1, Date().timeIntervalSince(startedAt) / duration)
                    DispatchQueue.main.async {
                        self?.bitrateCalibrationProgress = progress
                        self?.bitrateCalibrationStatus = "Calibrating link... \(Int(progress * 100))%"
                    }

                    Thread.sleep(forTimeInterval: 0.35)
                }
            }

            let result = Self.recommendBitrateKbps(
                probeResults: probeResults,
                failures: failures,
                attempts: attempts,
                resolution: resolution,
                fps: fps
            )

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                if let sliderIndex = result.sliderIndex {
                    self.bitrateSliderValue = Float(sliderIndex)
                }
                self.bitrateCalibrationProgress = 1
                self.isCalibratingBitrate = false
                self.bitrateCalibrationStatus = result.status
            }
        }
    }
    
    init() {
        if let hosts = Self.hosts {
            if let selectedProfile = UserDefaults.standard.string(forKey: "selectedSettingsProfile") {
                for (_, host) in hosts.enumerated() {
                    if let host {
                        if host.id == selectedProfile {
                            selectedHost = host
                        }
                    }
                }
            } else {
                if let firstHost = hosts.first {
                    selectedHost = firstHost
                }
            }
        }
        
        selectedResolution = Self.defaultResolution
        customResWidth = Self.defaultCustomResWidth
        customResHeight = Self.defaultCustomResHeight
        selectedFps = Self.defaultFps
        customFps = Self.defaultCustomFps
        
        bitrateSliderValue = Self.defaultBitrateSliderValue
        
        selectedVideoCodec = Self.defaultVideoCodec
        hdr = Self.defaultHdr
        selectedPacingOptions = Self.defaultPacingOptions
        
        audioOnPC = Self.defaultAudioOnPC
        disableAWDLDuringStream = Self.defaultDisableAWDLDuringStream
        volumeLevel = Self.defaultVolumeLevel
        
        selectedMultiControllerMode = Self.defaultMultiControllerMode
        swapButtons = Self.defaultSwapButtons
        
        optimize = Self.defaultOptimize
        
        autoFullscreen = Self.defaultAutoFullscreen
        rumble = Self.defaultRumble
        selectedControllerDriver = Self.defaultControllerDriver
        selectedMouseDriver = Self.defaultMouseDriver
        parsecMouseMode = Self.defaultParsecMouseMode
        selectedParsecMouseShortcut = Self.defaultParsecMouseShortcut
        parsecMouseShortcutKeyCode = Self.defaultParsecMouseShortcutKeyCode
        parsecMouseShortcutModifierMask = Self.defaultParsecMouseShortcutModifierMask
        parsecMouseShortcutDisplay = Self.defaultParsecMouseShortcut
        streamExitShortcutKeyCode = Self.defaultStreamExitShortcutKeyCode
        streamExitShortcutModifierMask = Self.defaultStreamExitShortcutModifierMask
        streamExitShortcutDisplay = Self.defaultStreamExitShortcut
        parsecMouseClientAuthoritativeCursor = Self.defaultParsecMouseClientAuthoritativeCursor
        parsecMouseEventDrivenPosition = Self.defaultParsecMouseEventDrivenPosition
        parsecMouseIdleHostCorrection = Self.defaultParsecMouseIdleHostCorrection
        parsecMouseDeltaAccumulatedVisibleCursor = Self.defaultParsecMouseDeltaAccumulatedVisibleCursor
        audioDiagnosticsEnabled = Self.defaultAudioDiagnosticsEnabled
        lowLatencyMousePipeline = Self.defaultLowLatencyMousePipeline

        emulateGuide = Self.defaultEmulateGuide
        selectedWindowsCtrlSource = Self.defaultWindowsCtrlSource
        selectedWindowsShiftSource = Self.defaultWindowsShiftSource
        selectedWindowsAltSource = Self.defaultWindowsAltSource
        selectedWindowsWinSource = Self.defaultWindowsWinSource
        appArtworkWidth = Self.defaultAppArtworkWidth
        appArtworkHeight = Self.defaultAppArtworkHeight
        dimNonHoveredArtwork = Self.defaultDimNonHoveredArtwork
    }

    func loadDefaultSettings() {
        selectedResolution = Self.defaultResolution
        customResWidth = Self.defaultCustomResWidth
        customResHeight = Self.defaultCustomResHeight
        selectedFps = Self.defaultFps
        customFps = Self.defaultCustomFps
        
        bitrateSliderValue = Self.defaultBitrateSliderValue
        
        selectedVideoCodec = Self.defaultVideoCodec
        hdr = Self.defaultHdr
        selectedPacingOptions = Self.defaultPacingOptions
        
        audioOnPC = Self.defaultAudioOnPC
        disableAWDLDuringStream = Self.defaultDisableAWDLDuringStream
        volumeLevel = Self.defaultVolumeLevel

        selectedMultiControllerMode = Self.defaultMultiControllerMode
        swapButtons = Self.defaultSwapButtons
        
        optimize = Self.defaultOptimize
        
        autoFullscreen = Self.defaultAutoFullscreen
        rumble = Self.defaultRumble
        selectedControllerDriver = Self.defaultControllerDriver
        selectedMouseDriver = Self.defaultMouseDriver
        parsecMouseMode = Self.defaultParsecMouseMode
        selectedParsecMouseShortcut = Self.defaultParsecMouseShortcut
        parsecMouseShortcutKeyCode = Self.defaultParsecMouseShortcutKeyCode
        parsecMouseShortcutModifierMask = Self.defaultParsecMouseShortcutModifierMask
        parsecMouseShortcutDisplay = Self.defaultParsecMouseShortcut
        streamExitShortcutKeyCode = Self.defaultStreamExitShortcutKeyCode
        streamExitShortcutModifierMask = Self.defaultStreamExitShortcutModifierMask
        streamExitShortcutDisplay = Self.defaultStreamExitShortcut
        parsecMouseClientAuthoritativeCursor = Self.defaultParsecMouseClientAuthoritativeCursor
        parsecMouseEventDrivenPosition = Self.defaultParsecMouseEventDrivenPosition
        parsecMouseIdleHostCorrection = Self.defaultParsecMouseIdleHostCorrection
        parsecMouseDeltaAccumulatedVisibleCursor = Self.defaultParsecMouseDeltaAccumulatedVisibleCursor
        audioDiagnosticsEnabled = Self.defaultAudioDiagnosticsEnabled
        lowLatencyMousePipeline = Self.defaultLowLatencyMousePipeline

        emulateGuide = Self.defaultEmulateGuide
        selectedWindowsCtrlSource = Self.defaultWindowsCtrlSource
        selectedWindowsShiftSource = Self.defaultWindowsShiftSource
        selectedWindowsAltSource = Self.defaultWindowsAltSource
        selectedWindowsWinSource = Self.defaultWindowsWinSource
        appArtworkWidth = Self.defaultAppArtworkWidth
        appArtworkHeight = Self.defaultAppArtworkHeight
        dimNonHoveredArtwork = Self.defaultDimNonHoveredArtwork
    }

    func loadAndSaveDefaultSettings() {
        loadDefaultSettings()
        saveSettings()
    }
    
    func loadSettings() {
        if let selectedHost {
            if let settings = Settings.getSettings(for: selectedHost.id) {
                selectedResolution = settings.resolution

                let customResolution = loadNillableDimensionSetting(inputDimensions: settings.customResolution)
                customResWidth = customResolution != nil ? customResolution!.width : nil
                customResHeight = customResolution != nil ? customResolution!.height : nil
                if customResolution == nil {
                    if selectedResolution == .zero {
                        selectedResolution = Self.defaultResolution
                    }
                }

                selectedFps = settings.fps
                customFps = settings.customFps
                if customFps == nil {
                    if selectedFps == 0 {
                        selectedFps = Self.defaultFps
                    }
                }
                
                var bitrateIndex = 0
                for i in 0..<Self.bitrateSteps.count {
                    if Float(settings.bitrate) <= Self.bitrateSteps[i] * 1000.0 {
                        bitrateIndex = i
                        break
                    }
                }
                bitrateSliderValue = Float(bitrateIndex)
                
                selectedVideoCodec = Self.getString(from: settings.codec, in: Self.videoCodecs)
                hdr = settings.hdr
                selectedPacingOptions = Self.pacingOption(fromStoredValue: settings.framePacing)
                
                audioOnPC = settings.audioOnPC
                disableAWDLDuringStream = settings.disableAWDLDuringStream ?? Self.defaultDisableAWDLDuringStream
                volumeLevel = settings.volumeLevel ?? SettingsModel.defaultVolumeLevel
                
                selectedMultiControllerMode = Self.getString(from: settings.multiController, in: Self.multiControllerModes)
                swapButtons = settings.swapABXYButtons
                
                optimize = settings.optimize
                
                autoFullscreen = settings.autoFullscreen
                rumble = settings.rumble
                selectedControllerDriver = Self.getString(from: settings.controllerDriver, in: Self.controllerDrivers)
                selectedMouseDriver = Self.getString(from: settings.mouseDriver, in: Self.mouseDrivers)
                parsecMouseMode = settings.parsecMouseMode ?? Self.defaultParsecMouseMode
                let legacyShortcutIndex = settings.parsecMouseShortcut ?? Self.defaultParsecMouseShortcutIndex
                selectedParsecMouseShortcut = Self.getString(from: legacyShortcutIndex, in: Self.parsecMouseShortcutOptions)
                parsecMouseShortcutKeyCode = settings.parsecMouseShortcutKeyCode ?? Self.keyCode(forParsecMouseShortcutIndex: legacyShortcutIndex)
                parsecMouseShortcutModifierMask = settings.parsecMouseShortcutModifierMask ?? Self.modifierMask(forParsecMouseShortcutIndex: legacyShortcutIndex)
                parsecMouseShortcutDisplay = settings.parsecMouseShortcutDisplay ?? Self.displayString(keyCode: parsecMouseShortcutKeyCode, modifierMask: parsecMouseShortcutModifierMask)
                streamExitShortcutKeyCode = settings.streamExitShortcutKeyCode ?? Self.defaultStreamExitShortcutKeyCode
                streamExitShortcutModifierMask = settings.streamExitShortcutModifierMask ?? Self.defaultStreamExitShortcutModifierMask
                streamExitShortcutDisplay = settings.streamExitShortcutDisplay ?? Self.displayString(keyCode: streamExitShortcutKeyCode, modifierMask: streamExitShortcutModifierMask)
                parsecMouseClientAuthoritativeCursor = settings.parsecMouseClientAuthoritativeCursor ?? Self.defaultParsecMouseClientAuthoritativeCursor
                parsecMouseEventDrivenPosition = settings.parsecMouseEventDrivenPosition ?? Self.defaultParsecMouseEventDrivenPosition
                parsecMouseIdleHostCorrection = settings.parsecMouseIdleHostCorrection ?? Self.defaultParsecMouseIdleHostCorrection
                parsecMouseDeltaAccumulatedVisibleCursor = settings.parsecMouseDeltaAccumulatedVisibleCursor ?? Self.defaultParsecMouseDeltaAccumulatedVisibleCursor
                audioDiagnosticsEnabled = settings.audioDiagnosticsEnabled ?? Self.defaultAudioDiagnosticsEnabled
                lowLatencyMousePipeline = settings.lowLatencyMousePipeline ?? Self.defaultLowLatencyMousePipeline

                emulateGuide = settings.emulateGuide
                selectedWindowsCtrlSource = Self.getString(from: settings.windowsCtrlSource ?? Self.defaultWindowsCtrlSourceIndex, in: Self.keyboardModifierSources)
                selectedWindowsShiftSource = Self.getString(from: settings.windowsShiftSource ?? Self.defaultWindowsShiftSourceIndex, in: Self.keyboardModifierSources)
                selectedWindowsAltSource = Self.getString(from: settings.windowsAltSource ?? Self.defaultWindowsAltSourceIndex, in: Self.keyboardModifierSources)
                selectedWindowsWinSource = Self.getString(from: settings.windowsWinSource ?? Self.defaultWindowsWinSourceIndex, in: Self.keyboardModifierSources)
                
                let appArtworkDimensions = loadNillableDimensionSetting(inputDimensions: settings.appArtworkDimensions)
                appArtworkWidth = appArtworkDimensions != nil ? appArtworkDimensions!.width : nil
                appArtworkHeight = appArtworkDimensions != nil ? appArtworkDimensions!.height : nil

                dimNonHoveredArtwork = settings.dimNonHoveredArtwork
                
                func loadNillableDimensionSetting(inputDimensions: CGSize?) -> CGSize? {
                    let finalSize: CGSize?
                    
                    if let nonNilDimensions = inputDimensions {
                        if nonNilDimensions.width == .zero || nonNilDimensions.height == .zero {
                            finalSize = nil
                        } else {
                            finalSize = nonNilDimensions
                        }
                    } else {
                        finalSize = nil
                    }
                    
                    return finalSize
                }
            } else {
                loadAndSaveDefaultSettings()
            }
        } else {
            loadAndSaveDefaultSettings()
        }
    }
    
    func saveSettings() {
        var customResolution: CGSize? = nil
        if let customResWidth, let customResHeight {
            if customResWidth == 0 || customResHeight == 0 {
                customResolution = nil
            } else {
                customResolution = CGSizeMake(CGFloat(customResWidth), CGFloat(customResHeight))
            }
        }
        
        var finalCustomFps: CGFloat? = nil
        if let customFps {
            if customFps == 0 {
                finalCustomFps = nil
            } else {
                finalCustomFps = customFps
            }
        }

        let bitrate = Int(Self.bitrateSteps[Int(bitrateSliderValue)] * 1000)
        let codec = Self.getInt(from: selectedVideoCodec, in: Self.videoCodecs)
        let framePacing = Self.storedValue(forPacingOption: selectedPacingOptions)
        let multiController = Self.getBool(from: selectedMultiControllerMode, in: Self.multiControllerModes)
        let controllerDriver = Self.getInt(from: selectedControllerDriver, in: Self.controllerDrivers)
        let mouseDriver = Self.getInt(from: selectedMouseDriver, in: Self.mouseDrivers)
        let parsecMouseShortcut = Self.getInt(from: selectedParsecMouseShortcut, in: Self.parsecMouseShortcutOptions)
        let windowsCtrlSource = Self.getInt(from: selectedWindowsCtrlSource, in: Self.keyboardModifierSources)
        let windowsShiftSource = Self.getInt(from: selectedWindowsShiftSource, in: Self.keyboardModifierSources)
        let windowsAltSource = Self.getInt(from: selectedWindowsAltSource, in: Self.keyboardModifierSources)
        let windowsWinSource = Self.getInt(from: selectedWindowsWinSource, in: Self.keyboardModifierSources)

        var appArtworkDimensions: CGSize? = nil
        if let appArtworkWidth, let appArtworkHeight {
            if appArtworkWidth == 0 || appArtworkHeight == 0 {
                appArtworkDimensions = nil
            } else {
                appArtworkDimensions = CGSizeMake(CGFloat(appArtworkWidth), CGFloat(appArtworkHeight))
            }
        }

        let settings = Settings(
            resolution: selectedResolution,
            customResolution: customResolution,
            fps: selectedFps,
            customFps: finalCustomFps,
            bitrate: bitrate,
            codec: codec,
            hdr: hdr,
            framePacing: framePacing,
            audioOnPC: audioOnPC,
            disableAWDLDuringStream: disableAWDLDuringStream,
            volumeLevel: volumeLevel,
            multiController: multiController,
            swapABXYButtons: swapButtons,
            optimize: optimize,
            autoFullscreen: autoFullscreen,
            rumble: rumble,
            controllerDriver: controllerDriver,
            mouseDriver: mouseDriver,
            parsecMouseMode: parsecMouseMode,
            parsecMouseShortcut: parsecMouseShortcut,
            parsecMouseShortcutKeyCode: parsecMouseShortcutKeyCode,
            parsecMouseShortcutModifierMask: parsecMouseShortcutModifierMask,
            parsecMouseShortcutDisplay: parsecMouseShortcutDisplay,
            streamExitShortcutKeyCode: streamExitShortcutKeyCode,
            streamExitShortcutModifierMask: streamExitShortcutModifierMask,
            streamExitShortcutDisplay: streamExitShortcutDisplay,
            parsecMouseClientAuthoritativeCursor: parsecMouseClientAuthoritativeCursor,
            parsecMouseEventDrivenPosition: parsecMouseEventDrivenPosition,
            parsecMouseIdleHostCorrection: parsecMouseIdleHostCorrection,
            parsecMouseDeltaAccumulatedVisibleCursor: parsecMouseDeltaAccumulatedVisibleCursor,
            audioDiagnosticsEnabled: audioDiagnosticsEnabled,
            lowLatencyMousePipeline: lowLatencyMousePipeline,
            emulateGuide: emulateGuide,
            windowsCtrlSource: windowsCtrlSource,
            windowsShiftSource: windowsShiftSource,
            windowsAltSource: windowsAltSource,
            windowsWinSource: windowsWinSource,
            appArtworkDimensions: appArtworkDimensions,
            dimNonHoveredArtwork: dimNonHoveredArtwork
        )
        
        if let data = try? PropertyListEncoder().encode(settings) {
            if let selectedHost {
                UserDefaults.standard.set(data, forKey: SettingsClass.profileKey(for: selectedHost.id))
            }
        }
    }
    
    static func getInt(from selectedSetting: String, in settingsArray: [String]) -> Int {
        for (index, setting) in settingsArray.enumerated() {
            if setting == selectedSetting {
                return index
            }
        }
        
        return 0
    }

    static func getString(from settingInt: Int, in settingsArray: [String]) -> String {
        var settingString = settingsArray.first!
        for (index, setting) in settingsArray.enumerated() {
            if index == settingInt {
                settingString = setting
            }
        }
        
        return settingString
    }

    static func keyCode(forParsecMouseShortcutIndex index: Int) -> Int {
        if parsecMouseShortcutKeyCodes.indices.contains(index) {
            return parsecMouseShortcutKeyCodes[index]
        }

        return defaultParsecMouseShortcutKeyCode
    }

    static func modifierMask(forParsecMouseShortcutIndex index: Int) -> UInt {
        if parsecMouseShortcutModifierMasks.indices.contains(index) {
            return parsecMouseShortcutModifierMasks[index]
        }

        return defaultParsecMouseShortcutModifierMask
    }

    static func displayString(keyCode: Int, modifierMask: UInt) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifierMask)
        if flags.contains(.control) {
            parts.append("Control")
        }
        if flags.contains(.option) {
            parts.append("Option")
        }
        if flags.contains(.shift) {
            parts.append("Shift")
        }
        if flags.contains(.command) {
            parts.append("Command")
        }
        if flags.contains(.function) {
            parts.append("Fn")
        }
        parts.append(keyLabel(forKeyCode: keyCode))
        return parts.joined(separator: " + ")
    }

    static func keyLabel(forKeyCode keyCode: Int) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 49: return "Space"
        case 50: return "`"
        case 53: return "Esc"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        default: return "Key \(keyCode)"
        }
    }

    static func storedValue(forPacingOption pacingOption: String) -> Int {
        switch pacingOption {
        case pacingLowestLatency:
            return 0
        case pacingSmoothest:
            return 1
        case pacingAuto:
            return 2
        case pacingBalanced:
            return 3
        default:
            return 2
        }
    }

    static func pacingOption(fromStoredValue storedValue: Int) -> String {
        switch storedValue {
        case 0:
            return pacingLowestLatency
        case 1:
            return pacingSmoothest
        case 2:
            return pacingAuto
        case 3:
            return pacingBalanced
        default:
            return defaultPacingOptions
        }
    }

    static func getBool(from settingInt: Int, in settingsArray: [String]) -> Bool {
        guard settingsArray.count == 2 || settingInt <= 1 else {
            return false
        }
        
        var settingBool = false
        for (index, _) in settingsArray.enumerated() {
            if index == settingInt {
                settingBool = index == 1
            }
        }
        
        return settingBool
    }

    static func getBool(from selectedSetting: String, in settingsArray: [String]) -> Bool {
        selectedSetting == settingsArray.last
    }
    
    static func getString(from settingBool: Bool, in settingsArray: [String]) -> String {
        var settingString = settingsArray.first!
        for (index, setting) in settingsArray.enumerated() {
            let indexBool = index == 1
            if indexBool == settingBool {
                settingString = setting
            }
        }
        
        return settingString
    }

    private var effectiveResolution: CGSize {
        if selectedResolution == .zero {
            return CGSize(
                width: customResWidth ?? Self.defaultResolution.width,
                height: customResHeight ?? Self.defaultResolution.height
            )
        }

        return selectedResolution
    }

    private var effectiveFps: Int {
        if selectedFps == .zero {
            return Int(customFps ?? CGFloat(Self.defaultFps))
        }

        return selectedFps
    }

    private struct BitrateCalibrationResult {
        let sliderIndex: Int?
        let status: String
    }

    private static func currentCalibrationAddress(for host: Host) -> String? {
        guard let tempHosts = DataManager().getHosts() as? [TemporaryHost],
              let tempHost = tempHosts.first(where: { $0.uuid == host.id }) else {
            return nil
        }

        return calibrationAddress(for: tempHost)
    }

    private static func calibrationAddress(for host: TemporaryHost) -> String {
        if let address = host.address, Utils.port(fromAddressString: address) != nil {
            return address
        }

        if let activeAddress = host.activeAddress, Utils.port(fromAddressString: activeAddress) != nil {
            return activeAddress
        }

        return host.activeAddress ?? host.localAddress ?? host.address ?? host.externalAddress ?? host.ipv6Address ?? ""
    }

    private static func measureHostProbe(address: String) -> TimeInterval? {
        let host = Utils.host(fromAddressString: address) ?? address
        let explicitPort = Utils.port(fromAddressString: address).flatMap(UInt16.init)
        let ports: [UInt16]
        if let explicitPort {
            ports = [explicitPort]
        } else {
            ports = [47989, 47984, 48010]
        }

        for port in ports {
            if let latency = measureTcpConnect(host: host, port: port) {
                return latency
            }
        }

        return nil
    }

    private static func measureTcpConnect(host: String, port: UInt16) -> TimeInterval? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return nil
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        let startTime = Date()
        var measuredLatency: TimeInterval?

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                measuredLatency = Date().timeIntervalSince(startTime)
                connection.cancel()
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: DispatchQueue.global(qos: .userInitiated))

        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            connection.cancel()
        }

        return measuredLatency
    }

    private static func recommendBitrateKbps(probeResults: [TimeInterval?], failures: Int, attempts: Int, resolution: CGSize, fps: Int) -> BitrateCalibrationResult {
        let safeAttempts = max(attempts, 1)
        let lossRate = Double(failures) / Double(safeAttempts)
        let samples = probeResults.compactMap { $0 }
        guard !samples.isEmpty else {
            return BitrateCalibrationResult(
                sliderIndex: nil,
                status: "Calibration failed: the selected host did not accept calibration probes."
            )
        }

        let sortedSamples = samples.sorted()
        let medianMs = percentile(sortedSamples, percentile: 0.50) * 1000
        let p95Ms = percentile(sortedSamples, percentile: 0.95) * 1000
        let jitterMs = averageDelta(samples) * 1000

        let profileMaxMbps = maxBitrateForStream(resolution: resolution, fps: fps)
        let gccEstimateMbps = googleCongestionControlEstimateMbps(
            probeResults: probeResults,
            profileMaxMbps: profileMaxMbps
        )
        let recommendedMbps = max(1, min(150, gccEstimateMbps))
        let sliderIndex = sliderIndexForBitrateMbps(recommendedMbps)
        let sliderMbps = Int(bitrateSteps[sliderIndex])
        let status = String(
            format: "GCC calibrated to %d Mbps. Median %.0f ms, p95 %.0f ms, jitter %.0f ms, loss %.0f%%.",
            sliderMbps,
            medianMs,
            p95Ms,
            jitterMs,
            lossRate * 100
        )

        return BitrateCalibrationResult(sliderIndex: sliderIndex, status: status)
    }

    private static func googleCongestionControlEstimateMbps(probeResults: [TimeInterval?], profileMaxMbps: Double) -> Double {
        let successfulSamples = probeResults.compactMap { $0 }
        guard !successfulSamples.isEmpty else {
            return 1
        }

        let windowSize = 4
        let initialMbps = min(profileMaxMbps, max(6, profileMaxMbps * 0.50))
        var estimatedMbps = initialMbps
        var baselineDelay = percentile(successfulSamples.sorted(), percentile: 0.20)

        for windowStart in stride(from: 0, to: probeResults.count, by: windowSize) {
            let windowEnd = min(windowStart + windowSize, probeResults.count)
            let window = Array(probeResults[windowStart..<windowEnd])
            let windowAttempts = max(window.count, 1)
            let windowSamples = window.compactMap { $0 }
            let windowFailures = windowAttempts - windowSamples.count
            let windowLossRate = Double(windowFailures) / Double(windowAttempts)

            guard !windowSamples.isEmpty else {
                estimatedMbps *= 0.85
                continue
            }

            let sortedWindowSamples = windowSamples.sorted()
            let windowMedian = percentile(sortedWindowSamples, percentile: 0.50)
            let windowP95 = percentile(sortedWindowSamples, percentile: 0.95)
            let delayOveruseThreshold = max(0.010, baselineDelay * 0.50)
            let p95OveruseThreshold = max(0.020, baselineDelay)
            let isDelayOveruse = windowMedian > baselineDelay + delayOveruseThreshold ||
                windowP95 > baselineDelay + p95OveruseThreshold

            if windowLossRate > 0.10 {
                estimatedMbps *= max(0.50, 1 - (0.5 * windowLossRate))
            } else if isDelayOveruse {
                estimatedMbps *= 0.85
            } else if windowLossRate < 0.02 {
                estimatedMbps *= 1.05
                baselineDelay = min(baselineDelay, windowMedian)
            }

            estimatedMbps = max(1, min(profileMaxMbps, estimatedMbps))
        }

        return estimatedMbps
    }

    private static func maxBitrateForStream(resolution: CGSize, fps: Int) -> Double {
        let width = max(Double(resolution.width), 1)
        let height = max(Double(resolution.height), 1)
        let frames = max(Double(fps), 1)
        let relativePixelRate = (width * height * frames) / (1920 * 1080 * 60)
        let recommended = 40 * relativePixelRate

        return max(6, min(150, recommended))
    }

    private static func sliderIndexForBitrateMbps(_ bitrateMbps: Double) -> Int {
        var selectedIndex = 0

        for (index, step) in bitrateSteps.enumerated() {
            if Double(step) <= bitrateMbps {
                selectedIndex = index
            } else {
                break
            }
        }

        return selectedIndex
    }

    private static func percentile(_ samples: [TimeInterval], percentile: Double) -> TimeInterval {
        guard !samples.isEmpty else {
            return 0
        }

        let index = min(samples.count - 1, max(0, Int(Double(samples.count - 1) * percentile)))
        return samples[index]
    }

    private static func averageDelta(_ samples: [TimeInterval]) -> TimeInterval {
        guard samples.count > 1 else {
            return 0
        }

        var totalDelta: TimeInterval = 0
        for index in 1..<samples.count {
            totalDelta += abs(samples[index] - samples[index - 1])
        }

        return totalDelta / Double(samples.count - 1)
    }

    private struct ResolutionOption {
        let size: CGSize
        let label: String
    }

    private static func buildResolutionOptions() -> [ResolutionOption] {
        var options: [ResolutionOption] = []
        var seenSizes = Set<String>()

        func append(_ size: CGSize, label: String? = nil) {
            let normalizedSize = CGSize(width: size.width.rounded(), height: size.height.rounded())
            guard normalizedSize.width > 0, normalizedSize.height > 0 else {
                return
            }

            let key = "\(Int(normalizedSize.width))x\(Int(normalizedSize.height))"
            guard !seenSizes.contains(key) else {
                return
            }

            seenSizes.insert(key)
            options.append(ResolutionOption(size: normalizedSize, label: label ?? resolutionLabel(for: normalizedSize)))
        }

        append(CGSize(width: 1280, height: 720))
        append(CGSize(width: 1920, height: 1080))
        append(CGSize(width: 1920, height: 1200))
        append(CGSize(width: 2560, height: 1440))
        append(CGSize(width: 2560, height: 1600))
        append(CGSize(width: 2880, height: 1800))
        append(CGSize(width: 3840, height: 2160))

        if let screen = NSScreen.main {
            let scale = screen.backingScaleFactor
            let nativeSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
            append(nativeSize, label: "Native Display")

            if #available(macOS 12.0, *) {
                let safeAreaInsets = screen.safeAreaInsets
                let safeWidth = (screen.frame.width - safeAreaInsets.left - safeAreaInsets.right) * scale
                let safeHeight = (screen.frame.height - safeAreaInsets.top - safeAreaInsets.bottom) * scale
                let safeSize = CGSize(width: safeWidth, height: safeHeight)

                if safeSize != nativeSize {
                    append(safeSize, label: "Native Display (Notch-Free)")
                }
            }
        }

        options.append(ResolutionOption(size: .zero, label: "Custom"))
        return options
    }

    private static func resolutionLabel(for resolution: CGSize) -> String {
        let width = Int(resolution.width)
        let height = Int(resolution.height)

        if width == 3840 && height == 2160 {
            return "4K"
        }

        if width * 9 == height * 16 {
            return "\(height)p"
        }

        return "\(width) x \(height)"
    }
}
