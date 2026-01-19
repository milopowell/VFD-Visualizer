//
//  ContentView.swift
//  VFD Visualizer
//
//  Created by Milo Powell on 1/15/26.
//


import SwiftUI

struct ContentView: View {
    @StateObject var captureManager = CaptureManager()
    @State private var showSettings = false
    @State private var showHzAxis = true
    @State private var isDarkMode = true
    @State private var showBorder = true
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            (isDarkMode ? Color.black : Color(white: 0.9)).ignoresSafeArea()
            
            VStack(spacing: 0){
                HStack {
                    statusIndicator
                    Spacer()
                    Button(action: { showSettings.toggle() }){
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.cyan)
                    }
                }
                .padding()
                
                // Main Visualizer
                MetalVisualizerView(captureManager: captureManager, isDarkMode: isDarkMode)
                    .frame(minWidth: 800, minHeight: 400)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isDarkMode ? Color.cyan.opacity(1) : Color.gray.opacity(1), lineWidth: showBorder ? 10 : 0)
                    )
                    .padding(showBorder ? 20 : 0)
                    .background(isDarkMode ? Color.black : Color(white: 0.9))
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                
                if showHzAxis {
                    FrequencyAxisView(isDarkMode: isDarkMode)
                        .frame(height: 30)
                        .padding(.bottom, 10)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(captureManager: captureManager,
                         showHzAxis: $showHzAxis,
                         isDarkMode: $isDarkMode,
                         showBorder: $showBorder)
                .presentationDetents([.height(300)])
                .presentationBackground(.ultraThinMaterial)
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
                        .foregroundColor(isDarkMode ? .white : .black)
                }
                .padding(8)
                .cornerRadius(4)
            }
        }
    }

        struct FrequencyAxisView: View {
            let ticks = ["20Hz", "100Hz", "500Hz", "1kHz", "5kHz", "10kHz", "20kHz"]
            var isDarkMode: Bool
            
            var body: some View {
                HStack {
                    ForEach(ticks, id: \.self) { tick in
                        Text(tick)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(isDarkMode ? .cyan.opacity(0.8) : .blue)
                            .shadow(color: isDarkMode ? .cyan.opacity(0.5) : .clear, radius: isDarkMode ? 3 : 0)
                        if tick != ticks.last { Spacer() }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        
struct SettingsView: View {
    @ObservedObject var captureManager: CaptureManager
    @Binding var showHzAxis: Bool
    @Binding var isDarkMode: Bool
    @Binding var showBorder: Bool
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
                   
                    // Dark Mode
                    HStack {
                        Toggle("Dark Mode", isOn: $isDarkMode)
                    }
                    
                    // Frequency X Axis
                    HStack {
                        Toggle("Show Frequency Axis (Hz)", isOn: $showHzAxis)
                    }
                    
                    // Bezel Frame
                    HStack {
                        Toggle("Show Bezel Frame", isOn: $showBorder)
                    }
                    
                    // Peaks: Yes / No
                    HStack {
                        Toggle("Show Falling Peaks", isOn: $captureManager.showPeaks)
                    }
                    
                    // Bar num
                    HStack{
                        Picker("Bar Count", selection: $captureManager.numBars) {
                            Text("16 Bars").tag(16)
                            Text("32 Bars").tag(32)
                            Text("64 Bars").tag(64)
                        }
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
       
