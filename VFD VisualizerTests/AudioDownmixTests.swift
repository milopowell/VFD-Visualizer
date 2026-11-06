//
//  AudioDownmixTests.swift
//  VFD VisualizerTests
//

import XCTest
import CoreAudio
@testable import VFD_Visualizer

final class AudioDownmixTests: XCTestCase {
    private let left: [Float] = (0..<framesPerBuffer).map { Float($0) / 2048 }
    private let right: [Float] = (0..<framesPerBuffer).map { 1 - Float($0) / 1024 }

    private func downmix(_ layout: ChannelLayout, left: [Float], right: [Float]? = nil) -> [Float]? {
        var result: [Float]?
        withBufferList(left: left, right: right, layout: layout) { list in
            withMonoSamples(in: list) { result = Array($0) }
        }
        return result
    }

    private func assertClose(_ a: [Float]?, _ b: [Float], file: StaticString = #filePath, line: UInt = #line) {
        guard let a = a else { return XCTFail("No samples", file: file, line: line) }
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        XCTAssertTrue(zip(a, b).allSatisfy { abs($0 - $1) < 1e-5 }, file: file, line: line)
    }

    func testPlanarStereoAveragesChannels() {
        assertClose(downmix(.planar, left: left, right: right), zip(left, right).map { ($0 + $1) / 2 })
    }

    func testInterleavedStereoAveragesChannels() {
        assertClose(downmix(.interleaved, left: left, right: right), zip(left, right).map { ($0 + $1) / 2 })
    }

    func testMonoPassesThroughUnchanged() {
        assertClose(downmix(.mono, left: left), left)
    }

    func testFrameCountIsFramesNotSamples() {
        XCTAssertEqual(downmix(.interleaved, left: left, right: right)?.count, framesPerBuffer)
    }

    func testEmptyBufferListIsIgnored() {
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(list.unsafeMutablePointer) }
        list[0] = AudioBuffer(mNumberChannels: 0, mDataByteSize: 4096, mData: nil)
        var called = false
        withMonoSamples(in: list.unsafePointer) { _ in called = true }
        XCTAssertFalse(called)
    }

    // A known limit of averaging, recorded here so that any change to it is deliberate
    func testOppositePhaseChannelsCancel() {
        let mono = downmix(.planar, left: left, right: left.map { -$0 })
        XCTAssertEqual(mono?.map(abs).max(), 0)
    }

    func testTapFormatCheck() {
        var format = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat, mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        XCTAssertTrue(isSupportedTapFormat(format))

        format.mFormatFlags = kAudioFormatFlagIsSignedInteger
        XCTAssertFalse(isSupportedTapFormat(format), "Integer audio would be misread as floats")

        format.mFormatFlags = kAudioFormatFlagIsFloat
        format.mSampleRate = 0
        XCTAssertFalse(isSupportedTapFormat(format), "The FFT needs a real sample rate")
    }

    // Stereo must reach the same bar as the same tone in mono. Mixing the channels
    // together, as the app once did, moved interleaved audio to about half its pitch.
    func testStereoLayoutsReachTheSameBarAsMono() {
        for hz in [1000.0, 5000.0] {
            let tone: [Float] = (0..<framesPerBuffer).map { Float(0.1 * sin(2 * .pi * hz * Double($0) / 48000)) }
            var bars: [ChannelLayout: Int] = [:]
            for layout in [ChannelLayout.mono, .planar, .interleaved] {
                let engine = makeEngine()
                for _ in 0..<25 {
                    withBufferList(left: tone, right: layout == .mono ? nil : tone, layout: layout) { list in
                        withMonoSamples(in: list) { engine.processAudioSamples($0.baseAddress, count: Int32($0.count)) }
                    }
                    Thread.sleep(forTimeInterval: bufferInterval)
                }
                bars[layout] = loudestBar(of: engine)
            }
            XCTAssertEqual(bars[.planar], bars[.mono], "\(hz) Hz")
            XCTAssertEqual(bars[.interleaved], bars[.mono], "\(hz) Hz")
        }
    }
}
