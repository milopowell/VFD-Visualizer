//
//  ContentView.swift
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//


import SwiftUI
import Combine

struct ContentView: View {
    @StateObject var captureManager = CaptureManager()
    // Listens for what's playing in Apple Music or Spotify
    @StateObject private var nowPlaying = NowPlayingMonitor()
    @State private var showSettings = false
    // Display settings, saved between launches
    @AppStorage(SettingKeys.showFrequencyAxis) private var showHzAxis = SettingDefaults.showFrequencyAxis
    @AppStorage(SettingKeys.showBezel) private var showBorder = SettingDefaults.showBezel
    @AppStorage(SettingKeys.themeName) private var themeName = SettingDefaults.themeName
    @AppStorage(SettingKeys.showCPU) private var showCPU = SettingDefaults.showCPU
    @AppStorage(SettingKeys.showNowPlaying) private var showNowPlaying = SettingDefaults.showNowPlaying

    // The selected theme. It's saved by name, so the choice survives changes to the theme list.
    private var theme: ColorTheme { ColorTheme.named(themeName) }
    @State private var cpuUsage: Double = 0.0
    
    let cpuTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0){
                HStack {
                    statusIndicator
                    // Explain any capture problem next to the status indicator
                    if let problem = captureManager.captureProblem {
                        CaptureProblemView(problem: problem, theme: theme)
                    }
                    Spacer()
                    // What's playing in Apple Music or Spotify, unless a capture problem needs the space
                    if showNowPlaying, captureManager.captureProblem == nil, let track = nowPlaying.track {
                        NowPlayingView(track: track, color: theme.accentColor)
                        Spacer()
                    }
                    if showCPU {
                        cpuIndicator
                    }
                    Button(action: { showSettings.toggle() }){
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(theme.accentColor)
                    }
                }
                .padding()
                // Leave room for the close, minimize, and zoom buttons, which sit over this corner without a title bar
                .padding(.leading, 60)
                
                // Main Visualizer
                MetalVisualizerView(
                    captureManager: captureManager,
                    theme: theme
                )
                .frame(minWidth: 800, minHeight: 400)
                // Bezel edge: a fine line in the theme color around the display glass
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.accentColor.opacity(0.35), lineWidth: showBorder ? 2 : 0)
                )
                .padding(showBorder ? 14 : 0)
                // Faceplate: a dark frame, a little lighter than the background, like the panel around a hardware display
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(showBorder ? 0.12 : 0))
                )
                .padding(showBorder ? 6 : 0) // 14 + 6 keeps the 20 pt inset that the frequency axis lines up with
                .background(theme.backgroundColor)
                
                if showHzAxis {
                    FrequencyAxisView(theme: theme)
                        .frame(height: 30)
                        .padding(.horizontal, showBorder ? 20 : 0) // Match the visualizer's width
                        .padding(.bottom, 10)
                }
            }
        }
        // Start listening for track changes
        .onAppear { nowPlaying.start() }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                captureManager: captureManager,
                showHzAxis: $showHzAxis,
                showBorder: $showBorder,
                themeName: $themeName,
                showCPU: $showCPU,
                showNowPlaying: $showNowPlaying
            )
            .presentationDetents([.height(400)])
            .presentationBackground(.ultraThinMaterial)
        }
        .onReceive(cpuTimer) { _ in
            if showCPU {
                cpuUsage = getCPUUsage()
            }
        }
    }
    
    var statusIndicator: some View {
        Button(action: {
            if captureManager.isRecording {
                captureManager.stopStream()
            } else {
                Task { await captureManager.startStream() }
            }
        }) {
            HStack {
                Circle()
                    .fill(captureManager.isRecording ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: captureManager.isRecording ? .green : .red, radius: 4)
                // Status label in dot-matrix characters, like a VFD panel
                DotMatrixText(text: captureManager.isRecording ? "SYSTEM ACTIVE" : "OFFLINE", color: theme.accentColor)
            }
            .padding(8)
            .cornerRadius(4)
        }
    }
    
    var cpuIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .foregroundColor(theme.accentColor)
            // CPU readout in dot-matrix characters, matching the status label
            DotMatrixText(text: String(format: "%.1f%%", cpuUsage), color: theme.accentColor)
        }
        .padding(8)
    }
    
    func getCPUUsage() -> Double {
        var kr: kern_return_t
        var task_info_count: mach_msg_type_number_t
        
        task_info_count = mach_msg_type_number_t(TASK_INFO_MAX)
        var tinfo = [integer_t](repeating: 0, count: Int(task_info_count))
        
        kr = task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), &tinfo, &task_info_count)
        if kr != KERN_SUCCESS {
            return 0.0
        }
        
        var thread_list: thread_act_array_t?
        var thread_count: mach_msg_type_number_t = 0
        defer {
            if let thread_list = thread_list {
                vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: thread_list)), vm_size_t(Int(thread_count) * MemoryLayout<thread_t>.stride))
            }
        }
        
        kr = task_threads(mach_task_self_, &thread_list, &thread_count)
        
        if kr != KERN_SUCCESS {
            return 0.0
        }
        
        var tot_cpu: Double = 0
        
        if let thread_list = thread_list {
            for j in 0 ..< Int(thread_count) {
                var thread_info_count = mach_msg_type_number_t(THREAD_INFO_MAX)
                var thinfo = [integer_t](repeating: 0, count: Int(thread_info_count))
                kr = thread_info(thread_list[j], thread_flavor_t(THREAD_BASIC_INFO),
                                &thinfo, &thread_info_count)
                if kr != KERN_SUCCESS {
                    return 0.0
                }
                
                let threadBasicInfo = convertThreadInfoToThreadBasicInfo(thinfo)
                
                if threadBasicInfo.flags != TH_FLAGS_IDLE {
                    tot_cpu += (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
        }
        
        return tot_cpu
    }
    
    func convertThreadInfoToThreadBasicInfo(_ threadInfo: [integer_t]) -> thread_basic_info {
        var result = thread_basic_info()
        
        result.user_time = time_value_t(seconds: threadInfo[0], microseconds: threadInfo[1])
        result.system_time = time_value_t(seconds: threadInfo[2], microseconds: threadInfo[3])
        result.cpu_usage = threadInfo[4]
        result.policy = threadInfo[5]
        result.run_state = threadInfo[6]
        result.flags = threadInfo[7]
        result.suspend_count = threadInfo[8]
        result.sleep_time = threadInfo[9]
        
        return result
    }
}

// Shows what's wrong with capture, next to the status indicator
struct CaptureProblemView: View {
    let problem: CaptureProblem
    var theme: ColorTheme

    var body: some View {
        HStack(spacing: 8) {
            // The message itself
            Text(problem.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.accentColor)
                .lineLimit(2)
            // When no sound is arriving, offer a shortcut to the permission's settings page
            if problem == .noAudioYet {
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }) {
                    // Drawn in the theme color, so it stays readable on every theme
                    Text("Open Settings")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.accentColor)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.accentColor, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

    struct FrequencyAxisView: View {
        // Each label and the frequency it marks
        let ticks: [(label: String, hz: Float)] = [
            ("50Hz", 50), ("100Hz", 100), ("500Hz", 500),
            ("1kHz", 1000), ("5kHz", 5000), ("10kHz", 10000)
        ]
        var theme: ColorTheme
        
        // Position from 0 to 1 on the same log scale DSPEngine uses for its bars
        func position(of hz: Float) -> CGFloat {
            CGFloat(log(hz / VFD_MIN_FREQUENCY) / log(VFD_MAX_FREQUENCY / VFD_MIN_FREQUENCY))
        }

        var body: some View {
            // Center each label on its frequency, across the full width of the display
            GeometryReader { geometry in
                ForEach(ticks, id: \.label) { tick in
                    // Smaller dots than the status label, and slightly dimmer
                    DotMatrixText(text: tick.label, color: theme.accentColor.opacity(0.8), pitch: 1.45)
                        .position(x: position(of: tick.hz) * geometry.size.width, y: geometry.size.height / 2)
                }
            }
        }
    }
        
struct SettingsView: View {
    @ObservedObject var captureManager: CaptureManager
    @Binding var showHzAxis: Bool
    @Binding var showBorder: Bool
    @Binding var themeName: String
    @Binding var showCPU: Bool
    @Binding var showNowPlaying: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // macOS-style Header
            HStack {
                Text("VFD Settings")
                    .font(.headline)
                Spacer()
                // Put every setting back to how the app first opens
                Button("Reset to Defaults") {
                    captureManager.resetToDefaults()
                    showHzAxis = SettingDefaults.showFrequencyAxis
                    showBorder = SettingDefaults.showBezel
                    themeName = SettingDefaults.themeName
                    showCPU = SettingDefaults.showCPU
                    showNowPlaying = SettingDefaults.showNowPlaying
                }
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction) // Allows hitting 'Enter' to close
            }
            .padding()
            .background(Color.black.opacity(0.1))

            Form {
                Section(header: Text("Signal Processing").font(.caption).bold()) {
                    VStack(alignment: .leading, spacing: 10) {
                        
                        // Gain
                        HStack {
                            Text("Gain")
                            Spacer()
                            Text("\(captureManager.gain, specifier: "%.0f")").foregroundColor(.secondary)
                        }
                        Slider(value: $captureManager.gain, in: 1...100)
                        
                        // Smoothing
                        HStack {
                            Text("Smoothing")
                            Spacer()
                            Text("\(captureManager.smoothing, specifier: "%.2f")").foregroundColor(.secondary)
                        }
                        Slider(value: $captureManager.smoothing, in: 0...0.99)
                        
                        // Gravity
                        HStack {
                            Text("Peak Gravity")
                            Spacer()
                            Text("\(captureManager.gravity, specifier: "%.3f")").foregroundColor(.secondary)
                        }
                        Slider(value: $captureManager.gravity, in: 0.001...0.02)
                        
                        // Peak hold time
                        HStack {
                            Text("Peak Hold")
                            Spacer()

                            HStack {
                                Text("\(captureManager.peakHoldTime) frames")
                                    .foregroundColor(.secondary)
                                        
                                Stepper("", value: $captureManager.peakHoldTime, in: 0...120)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                Section(header: Text("Appearance").font(.caption).bold()) {
                   
                    // Color Theme
                    Picker("Color Theme", selection: $themeName) {
                        ForEach(ColorTheme.themes, id: \.name) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                    
                    // Frequency X Axis
                    Toggle("Show Frequency Axis (Hz)", isOn: $showHzAxis)
                    // Bezel Frame
                    Toggle("Show Bezel Frame", isOn: $showBorder)
                    // Peaks: Yes / No
                    Toggle("Show Falling Peaks", isOn: $captureManager.showPeaks)
                    // Show cpu usage
                    Toggle("Show CPU Usage", isOn: $showCPU)
                    // Show what's playing in Apple Music or Spotify
                    Toggle("Show Now Playing", isOn: $showNowPlaying)
                    
                    // Bar num
                        Picker("Bar Count", selection: $captureManager.numBars) {
                            Text("16 Bars").tag(16)
                            Text("32 Bars").tag(32)
                            Text("64 Bars").tag(64)
                        }
                    }
                .padding()
            }
            .padding()
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 600) // Fixed size for the Mac pop-over/sheet
    }
}

// Color theme presets
struct ColorTheme {
    let name: String
    let activeColorLow: SIMD3<Float>
    let activeColorHigh: SIMD3<Float>
    let inactiveColor: SIMD3<Float>
    let backgroundColor: Color
    let accentColor: Color
    
    // The first theme is the one the app opens with
    static let themes: [ColorTheme] = [
        ColorTheme(
            name: "Phosphor",
            activeColorLow: SIMD3<Float>(0.20, 0.85, 0.74),
            activeColorHigh: SIMD3<Float>(0.75, 1.00, 0.95),
            inactiveColor: SIMD3<Float>(0.04, 0.14, 0.12),
            backgroundColor: Color(red: 0.01, green: 0.045, blue: 0.04),
            accentColor: Color(red: 0.38, green: 0.97, blue: 0.86)
        ),
        ColorTheme(
            name: "Classic VFD",
            activeColorLow: SIMD3<Float>(0.00, 0.90, 1.00),
            activeColorHigh: SIMD3<Float>(0.70, 0.35, 1.00),
            inactiveColor: SIMD3<Float>(0.02, 0.08, 0.12),
            backgroundColor: .black,
            accentColor: Color(red: 0.2, green: 0.85, blue: 1)
        ),
        ColorTheme(
            name: "Amber",
            activeColorLow: SIMD3<Float>(1.00, 0.50, 0.05),
            activeColorHigh: SIMD3<Float>(1.00, 0.86, 0.50),
            inactiveColor: SIMD3<Float>(0.13, 0.07, 0.02),
            backgroundColor: Color(red: 0.035, green: 0.02, blue: 0.008),
            accentColor: Color(red: 1, green: 0.66, blue: 0.18)
        ),
        ColorTheme(
            name: "Matrix",
            activeColorLow: SIMD3<Float>(0.00, 0.42, 0.08),
            activeColorHigh: SIMD3<Float>(0.60, 1.00, 0.60),
            inactiveColor: SIMD3<Float>(0.00, 0.09, 0.02),
            backgroundColor: Color(red: 0, green: 0.01, blue: 0),
            accentColor: Color(red: 0.25, green: 0.95, blue: 0.4)
        ),
        ColorTheme(
            name: "Deep Ocean",
            activeColorLow: SIMD3<Float>(0.00, 0.28, 0.85),
            activeColorHigh: SIMD3<Float>(0.40, 0.90, 1.00),
            inactiveColor: SIMD3<Float>(0.02, 0.06, 0.14),
            backgroundColor: Color(red: 0.01, green: 0.025, blue: 0.07),
            accentColor: Color(red: 0.3, green: 0.68, blue: 1)
        ),
        ColorTheme(
            name: "Sunset",
            activeColorLow: SIMD3<Float>(1.0, 0.5, 0.0),
            activeColorHigh: SIMD3<Float>(1.0, 0.0, 0.5),
            inactiveColor: SIMD3<Float>(0.1, 0.05, 0.0),
            backgroundColor: Color(red: 0.1, green: 0.05, blue: 0.0),
            accentColor: .orange
        ),
        ColorTheme(
            name: "Fire",
            activeColorLow: SIMD3<Float>(1.0, 1.0, 0.0),
            activeColorHigh: SIMD3<Float>(1.0, 0.0, 0.0),
            inactiveColor: SIMD3<Float>(0.1, 0.0, 0.0),
            backgroundColor: Color(red: 0.1, green: 0.0, blue: 0.0),
            accentColor: .red
        )
    ]

    // Looks up a theme by name, falling back to the first theme if that name no longer exists
    static func named(_ name: String) -> ColorTheme {
        themes.first { $0.name == name } ?? themes[0]
    }
}
