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
    @State private var showSettings = false
    @State private var showHzAxis = true
    @State private var showBorder = true
    @State private var selectedTheme = 0
    @State private var showCPU = false
    @State private var cpuUsage: Double = 0.0
    
    let cpuTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ColorTheme.themes[selectedTheme].backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0){
                HStack {
                    statusIndicator
                    Spacer()
                    if showCPU {
                        cpuIndicator
                    }
                    Button(action: { showSettings.toggle() }){
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(ColorTheme.themes[selectedTheme].accentColor)
                    }
                }
                .padding()
                
                // Main Visualizer
                MetalVisualizerView(
                    captureManager: captureManager,
                    theme: ColorTheme.themes[selectedTheme]
                )
                .frame(minWidth: 800, minHeight: 400)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(ColorTheme.themes[selectedTheme].accentColor.opacity(1), lineWidth: showBorder ? 10 : 0)
                )
                .padding(showBorder ? 20 : 0)
                .background(ColorTheme.themes[selectedTheme].backgroundColor)
                
                if showHzAxis {
                    FrequencyAxisView(theme: ColorTheme.themes[selectedTheme])
                        .frame(height: 30)
                        .padding(.bottom, 10)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                captureManager: captureManager,
                showHzAxis: $showHzAxis,
                showBorder: $showBorder,
                selectedTheme: $selectedTheme,
                showCPU: $showCPU
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
                Text(captureManager.isRecording ? "SYSTEM ACTIVE" : "OFFLINE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(ColorTheme.themes[selectedTheme].accentColor)
            }
            .padding(8)
            .cornerRadius(4)
        }
    }
    
    var cpuIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .foregroundColor(ColorTheme.themes[selectedTheme].accentColor)
            Text("\(cpuUsage, specifier: "%.1f")%")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(ColorTheme.themes[selectedTheme].accentColor)
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


    struct FrequencyAxisView: View {
        let ticks = ["20Hz", "100Hz", "500Hz", "1kHz", "5kHz", "10kHz", "20kHz"]
        var theme: ColorTheme
        
        var body: some View {
            HStack {
                ForEach(ticks, id: \.self) { tick in
                    Text(tick)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.accentColor.opacity(0.8))
                        .shadow(color: theme.accentColor.opacity(0.5), radius: 3)
                    if tick != ticks.last { Spacer() }
                }
            }
            .padding(.horizontal, 20)
        }
    }
        
struct SettingsView: View {
    @ObservedObject var captureManager: CaptureManager
    @Binding var showHzAxis: Bool
    @Binding var showBorder: Bool
    @Binding var selectedTheme: Int
    @Binding var showCPU: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // macOS-style Header
            HStack {
                Text("VFD Settings")
                    .font(.headline)
                Spacer()
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

                Section(header: Text("Apperance").font(.caption).bold()) {
                   
                    // Color Theme
                    Picker("Color Theme", selection: $selectedTheme) {
                        ForEach(0..<ColorTheme.themes.count, id: \.self) { index in
                            Text(ColorTheme.themes[index].name).tag(index)
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
    
    static let themes: [ColorTheme] = [
        ColorTheme(
            name: "Classic VFD",
            activeColorLow: SIMD3<Float>(0.0, 1.0, 1.0),
            activeColorHigh: SIMD3<Float>(1.0, 0.0, 0.0),
            inactiveColor: SIMD3<Float>(0.0, 0.0, 0.1),
            backgroundColor: .black,
            accentColor: .cyan
        ),
        ColorTheme(
            name: "Deep Ocean",
            activeColorLow: SIMD3<Float>(0.0, 0.4, 0.8),
            activeColorHigh: SIMD3<Float>(0.5, 0.0, 0.5),
            inactiveColor: SIMD3<Float>(0.9, 0.9, 0.9),
            backgroundColor: Color(white: 0.9),
            accentColor: .blue
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
            name: "Matrix",
            activeColorLow: SIMD3<Float>(0.0, 1.0, 0.0),
            activeColorHigh: SIMD3<Float>(0.0, 0.5, 0.0),
            inactiveColor: SIMD3<Float>(0.0, 0.1, 0.0),
            backgroundColor: .black,
            accentColor: .green
        ),
        ColorTheme(
            name: "Purple Haze",
            activeColorLow: SIMD3<Float>(0.5, 0.0, 1.0),
            activeColorHigh: SIMD3<Float>(1.0, 0.0, 0.5),
            inactiveColor: SIMD3<Float>(0.1, 0.0, 0.1),
            backgroundColor: Color(red: 0.05, green: 0.0, blue: 0.1),
            accentColor: .purple
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
}
