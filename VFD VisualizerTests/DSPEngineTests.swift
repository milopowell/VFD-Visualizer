//
//  DSPEngineTests.swift
//  VFD VisualizerTests
//

import XCTest
@testable import VFD_Visualizer

final class DSPEngineTests: XCTestCase {
    func testLoudAudioStaysOnTheDisplay() {
        let engine = makeEngine()
        // A full-volume tone at the default gain
        play([1000], into: engine, amplitude: 1)
        XCTAssertLessThanOrEqual(barValues(of: engine).max()!, 1)
        XCTAssertLessThanOrEqual(peakValues(of: engine).max()!, 1, "Peak caps above 1 are drawn off the display")

        // Then the same tone with the Gain slider at its maximum
        engine.setGain(100)
        play([1000], into: engine, amplitude: 1)
        XCTAssertLessThanOrEqual(barValues(of: engine).max()!, 1)
        XCTAssertLessThanOrEqual(peakValues(of: engine).max()!, 1)
    }

    func testSilenceRestsAtZero() {
        let engine = makeEngine()
        play([1000], into: engine, amplitude: 0)
        XCTAssertEqual(barValues(of: engine).min(), 0, "Negative bars take longer to reappear when sound returns")
        XCTAssertEqual(barValues(of: engine).max(), 0)
    }

    func testBarsAppearQuicklyAfterSilence() {
        let engine = makeEngine()
        // Start from silence
        play([1000], into: engine, amplitude: 0)
        // Find which bar a 1 kHz tone lights, using a separate engine
        let target: Int = {
            let reference = makeEngine()
            play([1000], into: reference, buffers: 15)
            return loudestBar(of: reference)
        }()
        // Two buffers of sound should be enough to light it
        play([1000], into: engine, buffers: 2)
        XCTAssertGreaterThan(barValues(of: engine)[target], 0)
    }

    func testQuietAudioIsNotLimited() {
        let engine = makeEngine()
        play([1000], into: engine, amplitude: 0.05)
        let loudest = barValues(of: engine).max()!
        XCTAssertGreaterThan(loudest, 0.3)
        XCTAssertLessThan(loudest, 1)
    }

    func testBarsSpan40HzTo20kHz() {
        XCTAssertEqual(VFD_MIN_FREQUENCY, 40)
        XCTAssertEqual(VFD_MAX_FREQUENCY, 20000)

        // The lowest tone in range lights the first bar
        let low = makeEngine(bars: 64)
        play([40], into: low)
        XCTAssertEqual(loudestBar(of: low), 0, accuracy: 1)

        // A tone near the top lights the last bar
        let high = makeEngine(bars: 64)
        play([19000], into: high)
        XCTAssertEqual(loudestBar(of: high), 63, accuracy: 1)
    }

    func testLowerTonesLightLowerBars() {
        var previous = -1
        for hz in [100.0, 500.0, 1000.0, 5000.0, 10000.0] {
            let engine = makeEngine()
            play([hz], into: engine)
            XCTAssertGreaterThan(loudestBar(of: engine), previous, "\(hz) Hz")
            previous = loudestBar(of: engine)
        }
    }

    func testBarCountIsLimitedToCapacity() {
        let engine = DSPEngineWrapper(size: 16)!
        XCTAssertEqual(engine.maxBars, 16)
        engine.setNumBars(64)
        XCTAssertEqual(engine.numberOfBars, 16)
        engine.setNumBars(0)
        XCTAssertEqual(engine.numberOfBars, 1)
    }

    func testRealSampleRateKeepsBarsInPlace() {
        // Plays a tone recorded at deviceRate into an engine set to engineRate, and returns the bar it lights
        func bar(_ hz: Double, deviceRate: Double, engineRate: Float) -> Int {
            let engine = makeEngine()
            engine.setSampleRate(engineRate)
            play([hz], into: engine, sampleRate: deviceRate)
            return loudestBar(of: engine)
        }
        // 5 kHz recorded at 44.1 kHz must land on the same bar as at 48 kHz
        let expected = bar(5000, deviceRate: 48000, engineRate: 48000)
        XCTAssertEqual(bar(5000, deviceRate: 44100, engineRate: 44100), expected)
    }

    // On these devices the top bars are above the highest frequency the FFT contains,
    // and reading them unguarded crashes.
    func testLowSampleRateDevicesLeaveTopBarsEmpty() {
        for rate in [24000.0, 16000.0, 8000.0] {
            let engine = makeEngine()
            engine.setSampleRate(Float(rate))
            play([1000], into: engine, sampleRate: rate)
            // The highest bar below the device's top frequency, which is half its sample rate
            let topUsableBar = Int(32 * log(rate / 2 / 40) / log(500.0))
            let bars = barValues(of: engine)
            XCTAssertEqual(bars[min(topUsableBar + 1, 31)...].max(), 0, "\(rate) Hz")
            XCTAssertGreaterThan(bars.max()!, 0, "\(rate) Hz")
        }
    }
}
