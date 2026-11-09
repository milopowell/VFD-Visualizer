//
//  TestSupport.swift
//  VFD VisualizerTests
//

import Foundation
import CoreAudio
@testable import VFD_Visualizer

let framesPerBuffer = 1024

// The engine limits itself to about 60 updates a second using the real clock,
// so tests feed it audio at roughly the pace a capture device would.
let bufferInterval: TimeInterval = 0.021

// Plays sine tones into an engine. Each tone is added to the same mono signal.
func play(_ tones: [Double], into engine: DSPEngineWrapper, sampleRate: Double = 48000, amplitude: Float = 0.1, buffers: Int = 25) {
    // Running sample position, so the tone continues smoothly across buffers
    var position = 0
    for _ in 0..<buffers {
        var samples = [Float](repeating: 0, count: framesPerBuffer)
        for i in 0..<framesPerBuffer {
            for hz in tones {
                samples[i] += amplitude * Float(sin(2 * .pi * hz * Double(position + i) / sampleRate))
            }
        }
        position += framesPerBuffer
        engine.processAudioSamples(samples, count: Int32(framesPerBuffer))
        Thread.sleep(forTimeInterval: bufferInterval)
    }
}

// An engine with room for 64 bars, showing the given count
func makeEngine(bars: Int32 = 32) -> DSPEngineWrapper {
    let engine = DSPEngineWrapper(size: 64)!
    engine.setNumBars(bars)
    return engine
}

// The current bar heights
func barValues(of engine: DSPEngineWrapper) -> [Float] {
    Array(UnsafeBufferPointer(start: engine.frequencyBuffer, count: Int(engine.numberOfBars)))
}

// The current peak cap heights
func peakValues(of engine: DSPEngineWrapper) -> [Float] {
    Array(UnsafeBufferPointer(start: engine.peakBuffer, count: Int(engine.numberOfBars)))
}

// Index of the tallest bar
func loudestBar(of engine: DSPEngineWrapper) -> Int {
    let bars = barValues(of: engine)
    return bars.indices.max { bars[$0] < bars[$1] }!
}

// Lets timers and other main-thread work run for a while
func spinRunLoop(for seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

// How the channels of a buffer are arranged
enum ChannelLayout {
    case mono, planar, interleaved
}

// Builds a real AudioBufferList in the given layout and passes it to `body`.
func withBufferList(left: [Float], right: [Float]? = nil, layout: ChannelLayout, body: (UnsafePointer<AudioBufferList>) -> Void) {
    var leftSamples = left
    var rightSamples = right ?? []
    var mixed = [Float]()
    // Interleaved audio alternates left and right samples in one buffer
    if layout == .interleaved {
        for i in left.indices { mixed += [left[i], right![i]] }
    }
    leftSamples.withUnsafeMutableBytes { leftBytes in
        rightSamples.withUnsafeMutableBytes { rightBytes in
            mixed.withUnsafeMutableBytes { mixedBytes in
                let list = AudioBufferList.allocate(maximumBuffers: layout == .planar ? 2 : 1)
                defer { free(list.unsafeMutablePointer) }
                switch layout {
                case .mono:
                    list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftBytes.count), mData: leftBytes.baseAddress)
                case .planar:
                    list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftBytes.count), mData: leftBytes.baseAddress)
                    list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightBytes.count), mData: rightBytes.baseAddress)
                case .interleaved:
                    list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(mixedBytes.count), mData: mixedBytes.baseAddress)
                }
                body(list.unsafePointer)
            }
        }
    }
}
