//
//  CaptureManager.swift
//  VFD Visualizer
//
//  Created by Milo Powell on 1/16/26.
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import Accelerate
import Combine

class CaptureManager: NSObject, ObservableObject, SCStreamOutput {
    
    @Published var gain: Float = 20.0 {
        didSet { audioEngine?.setGain(gain) }
    }
    @Published var smoothing: Float = 0.7 {
        didSet { audioEngine?.setSmoothing(smoothing) }
    }
    @Published var gravity: Float = 0.005 {
        didSet { audioEngine?.setGravity(gravity) }
    }
    @Published var numBars: Int = 32 {
        didSet { audioEngine?.setNumBars(Int32(numBars)) }
    }
    @Published var showPeaks: Bool = true
    
    @Published var peakHoldTime: Int = 30 {
        didSet { audioEngine?.setHoldTime(Int32(peakHoldTime)) }
    }

    let audioEngine = DSPEngineWrapper(size: 64)
    @Published var isRecording: Bool = false {
        didSet {
            if !isRecording {
                // Start decay when offline
                startDecay()
            } else {
                // Stop decay when online
                stopDecay()
            }
        }
    }
    
    
    private var stream: SCStream?
    private var decayTimer: Timer?
    
    // Helper to store converted float data to avoid re-allocating every frame
    //private var conversionBuffer = [Float]()
    
    func stopStream() {
        Task {
            do {
                try await stream?.stopCapture()
                await MainActor.run { self.isRecording = false }
            } catch { print("Failed to stop: \(error)") }
        }
    }
    
    func startStream() async {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return }
            
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            
            // Set specific audio format
            config.sampleRate = 48000
            config.channelCount = 2
            
            config.width = 16
            config.height = 16
            config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream?.startCapture()
            
            await MainActor.run { self.isRecording = true }
            print("Stream Started Successfully")
            
        } catch {
            print("Failed to start stream: \(error)")
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        withMonoSamples(in: sampleBuffer) { samples in
            // Pass to C++ Engine
            self.audioEngine?.processAudioSamples(samples.baseAddress, count: Int32(samples.count))
        }
    }
    
    // Decay animation
    private func startDecay() {
        // Run decay at 60fps
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in self?.applyDecay()
        }
    }
    
    private func stopDecay() {
        decayTimer?.invalidate()
        decayTimer = nil
    }
    
    private func applyDecay() {
        guard let engine = audioEngine,
        let freqPtr = engine.frequencyBuffer,
        let peakPtr = engine.peakBuffer else { return }

        let count = Int(engine.numberOfBars)
        
        // Decay frequency bars
        for i in 0..<count {
            if freqPtr[i] > 0 {
                freqPtr[i] -= Float(gravity) * 2.0 // Decay rate
                if freqPtr[i] < 0 { freqPtr[i] = 0 }
            }
        }
        
        // Decay peaks
        for i in 0..<count {
            if peakPtr[i] > 0 {
                peakPtr[i] -= Float(gravity)
                if peakPtr[i] < 0 { peakPtr[i] = 0 }
            }
        }
    }
}

// Calls `body` with one mono channel of audio. The FFT needs a single continuous
// signal, so the channels are averaged whether they arrive planar (one buffer per
// channel) or interleaved (one buffer of LRLR...).
func withMonoSamples(in sampleBuffer: CMSampleBuffer, body: (UnsafeMutableBufferPointer<Float>) -> Void) {
    let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
    
    guard frameCount > 0,
          let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
          let format = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee,
          format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
          format.mBitsPerChannel == 32 else { return }
    
    try? sampleBuffer.withAudioBufferList { buffers, _ in
        withUnsafeTemporaryAllocation(of: Float.self, capacity: frameCount) { mono in
            mono.initialize(repeating: 0)
            var totalChannels = 0
            
            for buffer in buffers {
                guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let channels = Int(buffer.mNumberChannels)
                let frames = min(frameCount, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
                
                for frame in 0..<frames {
                    for channel in 0..<channels {
                        mono[frame] += samples[frame * channels + channel]
                    }
                }
                totalChannels += channels
            }
            
            guard totalChannels > 0 else { return }
            for frame in 0..<frameCount {
                mono[frame] /= Float(totalChannels)
            }
            body(mono)
        }
    }
}
