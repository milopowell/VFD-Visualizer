//
//  CaptureManagerTests.swift
//  VFD VisualizerTests
//
//  These create real taps but never start them, because starting is what
//  needs the System Audio Recording permission.
//

import XCTest
@testable import VFD_Visualizer

private struct TestFailure: LocalizedError {
    var errorDescription: String? { "boom" }
}

final class CaptureManagerTests: XCTestCase {
    private func makeManager() -> CaptureManager {
        let manager = CaptureManager()
        manager.noAudioHintDelay = 0.1
        return manager
    }

    // MARK: Silence hint

    func testSilenceShowsTheHintWithoutStoppingCapture() {
        let manager = makeManager()
        manager.isRecording = true
        manager.watchForSilence()
        spinRunLoop(for: 0.3)
        XCTAssertEqual(manager.captureProblem, .noAudioYet)
        XCTAssertTrue(manager.isRecording)
    }

    func testSoundClearsTheHint() {
        let manager = makeManager()
        manager.isRecording = true
        manager.watchForSilence()
        spinRunLoop(for: 0.3)
        manager.audioDetected()
        XCTAssertNil(manager.captureProblem)
    }

    func testNoHintWhenSoundAlreadyArrived() {
        let manager = makeManager()
        manager.isRecording = true
        manager.audioDetected()
        manager.watchForSilence()
        spinRunLoop(for: 0.3)
        XCTAssertNil(manager.captureProblem)
    }

    func testNoHintAfterStopping() {
        let manager = makeManager()
        manager.isRecording = true
        manager.watchForSilence()
        manager.stopStream()
        spinRunLoop(for: 0.3)
        XCTAssertNil(manager.captureProblem)
        XCTAssertFalse(manager.isRecording)
    }

    // MARK: Failures

    func testFailureGoesOfflineWithItsReason() {
        let manager = makeManager()
        manager.isRecording = true
        manager.handleCaptureFailure(TestFailure())
        XCTAssertFalse(manager.isRecording)
        XCTAssertEqual(manager.captureProblem, .failed("boom"))
    }

    func testSoundDoesNotEraseARealFailure() {
        let manager = makeManager()
        manager.handleCaptureFailure(TestFailure())
        manager.audioDetected()
        XCTAssertEqual(manager.captureProblem, .failed("boom"))
    }

    func testFailureMessageNamesTheStepAndError() {
        let message = CoreAudioError(step: "Couldn't start", status: -1).errorDescription
        XCTAssertEqual(message, "Couldn't start (Core Audio error -1).")
        XCTAssertTrue(CaptureProblem.failed("boom").message.contains("boom"))
    }

    // MARK: Going offline

    func testBarsFallAfterAFailure() {
        let manager = makeManager()
        manager.isRecording = true
        let bars = manager.audioEngine!.frequencyBuffer!
        let peaks = manager.audioEngine!.peakBuffer!
        for i in 0..<32 {
            bars[i] = 0.8
            peaks[i] = 0.8
        }
        manager.handleCaptureFailure(TestFailure())
        spinRunLoop(for: 0.5)
        XCTAssertLessThan(bars[0], 0.8)
        XCTAssertLessThan(peaks[0], 0.8)
    }

    func testStoppingTwiceDoesNotDoubleTheFallSpeed() {
        func fall(stops: Int) -> Float {
            let manager = makeManager()
            manager.isRecording = true
            let bars = manager.audioEngine!.frequencyBuffer!
            for i in 0..<32 { bars[i] = 0.8 }
            for _ in 0..<stops { manager.stopStream() }
            spinRunLoop(for: 0.5)
            return 0.8 - bars[0]
        }
        XCTAssertEqual(fall(stops: 2), fall(stops: 1), accuracy: 0.08)
    }

    // MARK: Start attempts that finish late

    func testNormalStartGoesActive() throws {
        let manager = makeManager()
        manager.finishCaptureAttempt(manager.beginCaptureAttempt(), with: try SystemAudioTap())
        XCTAssertTrue(manager.isRecording)
        manager.stopStream()
        XCTAssertFalse(manager.isRecording)
    }

    func testStopDuringARestartStaysOffline() throws {
        let manager = makeManager()
        manager.isRecording = true
        let restart = manager.beginCaptureAttempt()
        manager.stopStream()
        manager.finishCaptureAttempt(restart, with: try SystemAudioTap())
        XCTAssertFalse(manager.isRecording, "A late restart must not resume capture after a stop")
    }

    func testOnlyTheNewestStartWins() throws {
        let manager = makeManager()
        let first = manager.beginCaptureAttempt()
        let second = manager.beginCaptureAttempt()
        manager.finishCaptureAttempt(first, with: try SystemAudioTap())
        XCTAssertFalse(manager.isRecording)
        manager.finishCaptureAttempt(second, with: try SystemAudioTap())
        XCTAssertTrue(manager.isRecording)
        manager.stopStream()
    }

    func testStartingAfterAStopWorks() throws {
        let manager = makeManager()
        manager.stopStream()
        manager.finishCaptureAttempt(manager.beginCaptureAttempt(), with: try SystemAudioTap())
        XCTAssertTrue(manager.isRecording)
        manager.stopStream()
    }

    // MARK: Tap setup

    func testTapReportsASampleRateAndStopsSafely() throws {
        let tap = try SystemAudioTap()
        XCTAssertGreaterThan(tap.sampleRate, 0)
        tap.stop()
        tap.stop()
    }
}
