//
//  SettingsView.swift
//  Moonlight for macOS
//
//  Created by Michael Kenny on 15/1/2024.
//  Copyright © 2024 Moonlight Game Streaming Project. All rights reserved.
//

import AppKit
import SwiftUI

enum SettingsPaneType: Int, CaseIterable {
    case stream
    case videoAndAudio
    case input
    case app
    case legacy
#if DEBUG
    case debug
#endif

    var title: String {
        switch self {
        case .stream:
            return "Stream"
        case .videoAndAudio:
            return "Video and Audio"
            
        case .input:
            return "Input"
        case .app:
            return "App"
        case .legacy:
            return "Legacy"
#if DEBUG
        case .debug:
            return "Debug"
#endif
        }
    }
    
    var symbol: String {
        switch self {
        case .stream:
            return "airplayvideo"
        case .videoAndAudio:
            return "video.fill"
        case .input:
            return "keyboard.fill"
        case .app:
            return "appclip"
        case .legacy:
            return "archivebox.fill"
#if DEBUG
        case .debug:
            return "wrench.and.screwdriver.fill"
#endif
        }
    }
    
    var color: Color {
        switch self {
        case .stream:
            return .blue
        case .videoAndAudio:
            return .orange
        case .input:
            return .purple
        case .app:
            return .pink
        case .legacy:
            return Color(hex: 0x65B741)
#if DEBUG
        case .debug:
            return .gray
#endif
        }
    }
}

// From: https://medium.com/@jakir/use-hex-color-in-swiftui-c19e6ab79220
extension Color {
    init(hex: Int, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: opacity
        )
    }
}

struct SettingsView: View {
    @StateObject var settingsModel = SettingsModel()
    
    @AppStorage("selected-settings-pane") private var selectedPane: SettingsPaneType = .stream

    var body: some View {
        NavigationView {
            Sidebar(selectedPane: $selectedPane)
            Detail(pane: selectedPane)
                .environmentObject(settingsModel)
        }
        .frame(minWidth: 575, minHeight: 275)
    }
}

struct Sidebar: View {
    @Binding var selectedPane: SettingsPaneType

    var body: some View {
        // This "selectionBinding" is needed to make selection work with a macOS 11 Big Sur compatible List() constructor
        let selectionBinding = Binding<SettingsPaneType?>(get: {
            selectedPane
        }, set: { newValue in
            if let newPane = newValue {
                selectedPane = newPane
            }
        })

        List(SettingsPaneType.allCases, id: \.self, selection: selectionBinding) { pane in
            PaneCellView(pane: pane)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }
}

struct Detail: View {
    var pane: SettingsPaneType

    @EnvironmentObject private var settingsModel: SettingsModel
    
    var body: some View {
        Group {
            switch pane {
            case .stream:
                SettingPaneLoader(settingsModel) {
                    StreamView()
                }
            case .videoAndAudio:
                SettingPaneLoader(settingsModel) {
                    VideoAndAudioView()
                }
            case .input:
                SettingPaneLoader(settingsModel) {
                    InputView()
                }
            case .app:
                SettingPaneLoader(settingsModel) {
                    AppView()
                }
            case .legacy:
                SettingPaneLoader(settingsModel) {
                    LegacyView()
                }
#if DEBUG
            case .debug:
                SettingPaneLoader(settingsModel) {
                    DebugView()
                }
#endif
            }
        }
        .environmentObject(settingsModel)
        .navigationSubtitle(pane.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let hosts = SettingsModel.hosts {
                    HStack {
                        Text("Profile:")
                        
                        Picker("", selection: $settingsModel.selectedHost) {
                            ForEach(hosts, id: \.self) { host in
                                if let host {
                                    Text(host.name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SettingPaneLoader<Content: View>: View {
    let settingsModel: SettingsModel
    let content: Content

    init(_ settingsModel: SettingsModel, @ViewBuilder content: () -> Content) {
        self.settingsModel = settingsModel
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                settingsModel.loadSettings()
            }
    }
}

struct PaneCellView: View {
    let pane: SettingsPaneType

    var body: some View {
        let iconSize = CGFloat(14)
        let containerSize = iconSize + (iconSize / 3)
        
        HStack(spacing: 6) {
            Image(systemName: pane.symbol)
                .adaptiveForegroundColor(.white)
                .font(.callout)
                .frame(width: containerSize, height: containerSize)
                .padding(1)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .foregroundColor(pane.color)
                )
            
            Text(pane.title)
        }
    }
}

struct StreamView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    @SwiftUI.State private var showCustomResolutionGroup = false
    @SwiftUI.State private var showCustomFpsGroup = false
    
    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Resolution and FPS") {
                    FormCell(title: "Resolution", contentWidth: 100, content: {
                        Picker("", selection: $settingsModel.selectedResolution) {
                            ForEach(SettingsModel.resolutions, id: \.self) { resolution in
                                Text(verbatim: SettingsModel.label(for: resolution))
                            }
                        }
                    })
                    
                    if showCustomResolutionGroup {
                        Divider()
                        
                        FormCell(title: "Custom Resolution", contentWidth: 0, content: {
                            DimensionsInputView(widthBinding: $settingsModel.customResWidth, heightBinding: $settingsModel.customResHeight, placeholderDimensions: CGSize(width: 3440, height: 1440))
                        })
                    }
                    
                    Divider()
                    
                    FormCell(title: "FPS", contentWidth: 100, content: {
                        Picker("", selection: $settingsModel.selectedFps) {
                            ForEach(SettingsModel.fpss, id: \.self) { fps in
                                if fps == .zero {
                                    Text("Custom")
                                } else {
                                    Text("\(fps)")
                                }
                            }
                        }
                    })
                    
                    if showCustomFpsGroup {
                        Divider()
                        
                        FormCell(title: "Custom FPS", contentWidth: 0, content: {
                            TextField("40", value: $settingsModel.customFps, formatter: NumberOnlyFormatter())
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.plain)
                                .fixedSize()
                        })
                    }
                }
                
                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Bitrate") {
                    VStack(alignment: .leading) {
                        let bitrate = Int(SettingsModel.bitrateSteps[Int(settingsModel.bitrateSliderValue)])
                        Text("\(bitrate) Mbps")
                            .availableMonospacedDigit()
                        Slider(value: $settingsModel.bitrateSliderValue, in: 0...Float(SettingsModel.bitrateSteps.count - 1), step: 1)

                        HStack(spacing: 8) {
                            Button(action: {
                                settingsModel.calibrateBitrate()
                            }, label: {
                                if settingsModel.isCalibratingBitrate {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "speedometer")
                                }

                                Text(settingsModel.isCalibratingBitrate ? "Calibrating..." : "Calibrate")
                            })
                            .disabled(settingsModel.isCalibratingBitrate)

                            if settingsModel.isCalibratingBitrate {
                                ProgressView(value: settingsModel.bitrateCalibrationProgress)
                                    .frame(maxWidth: 120)
                            }
                        }

                        if let bitrateCalibrationStatus = settingsModel.bitrateCalibrationStatus {
                            Text(bitrateCalibrationStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer()
                    .frame(height: 32)

                FormSection(title: "Network") {
                    ToggleCell(title: "Disable AWDL During Stream", boolBinding: $settingsModel.disableAWDLDuringStream)
                }
            }
            .padding()
            .onAppear {
                func updateCustomResolutionGroup() {
                    showCustomResolutionGroup = settingsModel.selectedResolution == .zero
                }
                func updateCustomFpsGroup() {
                    showCustomFpsGroup = settingsModel.selectedFps == .zero
                }
                
                updateCustomResolutionGroup()
                updateCustomFpsGroup()
                settingsModel.resolutionChangedCallback = {
                    withAnimation {
                        updateCustomResolutionGroup()
                    }
                }
                settingsModel.fpsChangedCallback = {
                    withAnimation {
                        updateCustomFpsGroup()
                    }
                }
            }
        }
    }
}

struct VideoAndAudioView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Video") {
                    FormCell(title: "Video Codec", contentWidth: 155, content: {
                        Picker("", selection: $settingsModel.selectedVideoCodec) {
                            ForEach(SettingsModel.videoCodecs, id: \.self) { codec in
                                Text(codec)
                            }
                        }
                    })
                    
                    Divider()
                    
                    ToggleCell(title: "HDR", boolBinding: $settingsModel.hdr)
                    
                    Divider()
                    
                    FormCell(title: "Frame Pacing", contentWidth: 285, content: {
                        Picker("", selection: $settingsModel.selectedPacingOptions) {
                            ForEach(SettingsModel.pacingOptions, id: \.self) { pacingOption in
                                Text(framePacingLabel(for: pacingOption))
                            }
                        }
                    })
                }
                
                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Audio") {
                    ToggleCell(title: "Play Sound on Host", boolBinding: $settingsModel.audioOnPC)

                    Divider()
                    
                    VStack(alignment: .center) {
                        Text("Volume")

                        let volume = Int(settingsModel.volumeLevel * 100)
                        Slider(value: $settingsModel.volumeLevel, in: 0.0...1.0) {
                            ZStack(alignment: .leading) {
                                Text("\(100)%")
                                    .availableMonospacedDigit()
                                    .hidden()
                                Text("\(volume)%")
                                    .availableMonospacedDigit()
                            }
                        } minimumValueLabel: {
                            Image(systemName: "speaker.wave.1.fill")
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                        } onEditingChanged: { changed in
                            
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func framePacingLabel(for pacingOption: String) -> String {
        switch pacingOption {
        case SettingsModel.pacingAuto:
            return "Auto - chooses based on FPS and display"
        case SettingsModel.pacingLowestLatency:
            return "Lowest Latency - recommended for 30 FPS"
        case SettingsModel.pacingBalanced:
            return "Balanced - recommended for 60/120 FPS"
        case SettingsModel.pacingSmoothest:
            return "Smoothest - video-first, may add latency"
        default:
            return pacingOption
        }
    }
}

struct InputView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Controller") {
                    FormCell(title: "Multi-Controller Mode", contentWidth: 88, content: {
                        Picker("", selection: $settingsModel.selectedMultiControllerMode) {
                            ForEach(SettingsModel.multiControllerModes, id: \.self) { mode in
                                Text(mode)
                            }
                        }
                    })
                    
                    Divider()
                    
                    ToggleCell(title: "Rumble Controller", boolBinding: $settingsModel.rumble)
                }
                
                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Buttons") {
                    ToggleCell(title: "Swap A/B and X/Y Buttons", boolBinding: $settingsModel.swapButtons)
                    
                    Divider()
                    
                    ToggleCell(title: "Emulate Guide Button", boolBinding: $settingsModel.emulateGuide)
                }
                
                Spacer()
                    .frame(height: 32)

                FormSection(title: "Keyboard") {
                    ModifierSourcePickerCell(title: "Windows Ctrl", selection: $settingsModel.selectedWindowsCtrlSource)

                    Divider()

                    ModifierSourcePickerCell(title: "Windows Shift", selection: $settingsModel.selectedWindowsShiftSource)

                    Divider()

                    ModifierSourcePickerCell(title: "Windows Alt", selection: $settingsModel.selectedWindowsAltSource)

                    Divider()

                    ModifierSourcePickerCell(title: "Windows Win", selection: $settingsModel.selectedWindowsWinSource)
                }

                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Drivers") {
                    FormCell(title: "Controller Driver", contentWidth: 88, content: {
                        Picker("", selection: $settingsModel.selectedControllerDriver) {
                            ForEach(SettingsModel.controllerDrivers, id: \.self) { mode in
                                Text(mode)
                            }
                        }
                    })
                    
                    Divider()
                    
                    FormCell(title: "Mouse Driver", contentWidth: 88, content: {
                        Picker("", selection: $settingsModel.selectedMouseDriver) {
                            ForEach(SettingsModel.mouseDrivers, id: \.self) { mode in
                                Text(mode)
                            }
                        }
                    })

                    Divider()

                    ToggleCell(title: "Parsec Mouse Mode", boolBinding: $settingsModel.parsecMouseMode)

                    Divider()

                    ParsecMouseShortcutCell()

                    Divider()

                    StreamExitShortcutCell()
                }
            }
            .padding()
        }
    }
}

struct ParsecMouseShortcutCell: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    @SwiftUI.State private var isRecording = false

    var body: some View {
        FormCell(title: "Parsec Mouse Shortcut", contentWidth: 260, content: {
            HStack(spacing: 8) {
                Text(isRecording ? "Hold shortcut keys..." : settingsModel.parsecMouseShortcutDisplay)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(isRecording ? "Cancel" : "Register New") {
                    isRecording.toggle()
                }
                .buttonStyle(.bordered)
            }
            .background(Group {
                if isRecording {
                    ShortcutCaptureView(
                        onComplete: { keyCode, modifierMask in
                            settingsModel.parsecMouseShortcutKeyCode = keyCode
                            settingsModel.parsecMouseShortcutModifierMask = modifierMask
                            settingsModel.parsecMouseShortcutDisplay = SettingsModel.displayString(
                                keyCode: keyCode,
                                modifierMask: modifierMask
                            )
                            isRecording = false
                        },
                        onCancel: {
                            isRecording = false
                        }
                    )
                    .frame(width: 0, height: 0)
                }
            })
        })
    }
}

struct StreamExitShortcutCell: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    @SwiftUI.State private var isRecording = false

    var body: some View {
        FormCell(title: "Exit Stream Shortcut", contentWidth: 260, content: {
            HStack(spacing: 8) {
                Text(isRecording ? "Hold shortcut keys..." : settingsModel.streamExitShortcutDisplay)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(isRecording ? "Cancel" : "Register New") {
                    isRecording.toggle()
                }
                .buttonStyle(.bordered)
            }
            .background(Group {
                if isRecording {
                    ShortcutCaptureView(
                        onComplete: { keyCode, modifierMask in
                            settingsModel.streamExitShortcutKeyCode = keyCode
                            settingsModel.streamExitShortcutModifierMask = modifierMask
                            settingsModel.streamExitShortcutDisplay = SettingsModel.displayString(
                                keyCode: keyCode,
                                modifierMask: modifierMask
                            )
                            isRecording = false
                        },
                        onCancel: {
                            isRecording = false
                        }
                    )
                    .frame(width: 0, height: 0)
                }
            })
        })
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    let onComplete: (Int, UInt) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ShortcutCaptureNSView()
        context.coordinator.start()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.start()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator {
        private let onComplete: (Int, UInt) -> Void
        private let onCancel: () -> Void
        private var monitor: Any?
        private var pressedKeyCodes = Set<UInt16>()
        private var capturedKeyCode: Int?
        private var capturedModifierMask: UInt = 0

        init(onComplete: @escaping (Int, UInt) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func start() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                self?.handle(event)
                return nil
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            let modifierFlags = Self.shortcutModifierFlags(from: event)

            switch event.type {
            case .keyDown:
                if event.keyCode == 53 {
                    cancel()
                    return
                }

                pressedKeyCodes.insert(event.keyCode)
                capturedKeyCode = Int(event.keyCode)
                if modifierFlags != 0 {
                    capturedModifierMask = modifierFlags
                }

            case .keyUp:
                pressedKeyCodes.remove(event.keyCode)
                if modifierFlags != 0 {
                    capturedModifierMask = modifierFlags
                }
                completeIfReleased(currentModifierMask: modifierFlags)

            case .flagsChanged:
                if modifierFlags != 0 {
                    capturedModifierMask = modifierFlags
                }
                completeIfReleased(currentModifierMask: modifierFlags)

            default:
                break
            }
        }

        private func completeIfReleased(currentModifierMask: UInt) {
            guard pressedKeyCodes.isEmpty, currentModifierMask == 0, let capturedKeyCode else {
                return
            }

            let finalModifierMask = capturedModifierMask
            stop()
            DispatchQueue.main.async {
                self.onComplete(capturedKeyCode, finalModifierMask)
            }
        }

        private func cancel() {
            stop()
            DispatchQueue.main.async {
                self.onCancel()
            }
        }

        private static func shortcutModifierFlags(from event: NSEvent) -> UInt {
            let allowedFlags: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]
            return (event.modifierFlags.intersection(allowedFlags)).rawValue
        }
    }
}

final class ShortcutCaptureNSView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

struct ModifierSourcePickerCell: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        FormCell(title: title, contentWidth: 105, content: {
            Picker("", selection: $selection) {
                ForEach(SettingsModel.keyboardModifierSources, id: \.self) { source in
                    Text(source)
                }
            }
        })
    }
}

struct AppView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Behaviour") {
                    ToggleCell(title: "Automatically Fullscreen Stream Window", boolBinding: $settingsModel.autoFullscreen)
                }
                
                Spacer()
                    .frame(height: 32)
                
                FormSection(title: "Visuals") {
                    ToggleCell(title: "Dim Non-Hovered Apps", boolBinding: $settingsModel.dimNonHoveredArtwork)
                    
                    Divider()

                    FormCell(title: "Custom Artwork Dimensions", contentWidth: 0, content: {
                        DimensionsInputView(widthBinding: $settingsModel.appArtworkWidth, heightBinding: $settingsModel.appArtworkHeight, placeholderDimensions: CGSize(width: 300, height: 400))
                    })
                }
            }
            .padding()
        }
    }
}

struct LegacyView: View {
    @EnvironmentObject private var settingsModel: SettingsModel
    
    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Geforce Experience") {
                    ToggleCell(title: "Optimize Game Settings", boolBinding: $settingsModel.optimize)
                }
            }
            .padding()
        }
    }
}

#if DEBUG
struct DebugView: View {
    @EnvironmentObject private var settingsModel: SettingsModel

    var body: some View {
        ScrollView {
            VStack {
                FormSection(title: "Parsec Mouse") {
                    ToggleCell(title: "Client-Authoritative Cursor", boolBinding: $settingsModel.parsecMouseClientAuthoritativeCursor)

                    Divider()

                    ToggleCell(title: "Event-Driven Position Sends", boolBinding: $settingsModel.parsecMouseEventDrivenPosition)

                    Divider()

                    ToggleCell(title: "Idle Host Position Correction", boolBinding: $settingsModel.parsecMouseIdleHostCorrection)

                    Divider()

                    ToggleCell(title: "Delta-Accumulated Visible Cursor", boolBinding: $settingsModel.parsecMouseDeltaAccumulatedVisibleCursor)
                }

                Spacer()
                    .frame(height: 32)

                FormSection(title: "Diagnostics") {
                    ToggleCell(title: "Audio Diagnostics Logging", boolBinding: $settingsModel.audioDiagnosticsEnabled)
                }
            }
            .padding()
        }
    }
}
#endif

struct ToggleCell: View {
    let title: String
    @Binding var boolBinding: Bool

    var body: some View {
        FormCell(title: title, contentWidth: 0, content: {
            Toggle("", isOn: $boolBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
        })
    }
}

struct DimensionsInputView: View {
    @Binding var widthBinding: CGFloat?
    @Binding var heightBinding: CGFloat?
    let placeholderDimensions: CGSize
    
    var body: some View {
        HStack(spacing: 4) {
            TextField(formatDimension(placeholderDimensions.width), value: $widthBinding, formatter: NumberOnlyFormatter())
                .multilineTextAlignment(.trailing)
            
            Text("×")
            
            TextField(formatDimension(placeholderDimensions.height), value: $heightBinding, formatter: NumberOnlyFormatter())
                .multilineTextAlignment(.leading)
        }
        .textFieldStyle(.plain)
        .fixedSize()
    }
    
    func formatDimension(_ dimension: CGFloat) -> String {
        return "\(Int(dimension))"
    }
}

struct FormSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        GroupBox(content: {
            VStack {
                Group {
                    content
                }
                .padding([.top], 1)
            }
            .padding([.top, .bottom], 6)
            .padding([.leading, .trailing], 6)
        }, label: {
            Text(title)
                .font(
                    .system(.body, design: .rounded)
                    .weight(.semibold)
                )
                .padding(.bottom, 6)
        })
    }
}

struct FormCell<Content: View>: View {
    let title: String
    let contentWidth: CGFloat
    let content: Content
    
    init(title: String, contentWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.contentWidth = contentWidth
        self.content = content()
    }
    
    var body: some View {
        HStack {
            Text(title)
            
            Spacer()
            
            content
                .if(contentWidth != 0, transform: { view in
                    view
                        .frame(width: contentWidth)
                })
        }
    }
}

extension CGSize: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        return SettingsView()
    } else {
        return Text("Not supported")
    }
}
