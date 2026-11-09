//
//  SettingsTests.swift
//  VFD VisualizerTests
//
//  Settings are saved between launches, except the bar count, and Reset to Defaults
//  puts everything back. Each test uses its own empty settings store.
//

import XCTest
@testable import VFD_Visualizer

final class SettingsTests: XCTestCase {
    func testFirstLaunchUsesTheDefaults() {
        let manager = CaptureManager(settings: freshSettings())
        XCTAssertEqual(manager.gain, SettingDefaults.gain)
        XCTAssertEqual(manager.smoothing, SettingDefaults.smoothing)
        XCTAssertEqual(manager.gravity, SettingDefaults.gravity)
        XCTAssertEqual(manager.peakHoldTime, SettingDefaults.peakHoldTime)
        XCTAssertEqual(manager.showPeaks, SettingDefaults.showPeaks)
        XCTAssertEqual(manager.numBars, 16)
    }

    func testChangedSettingsComeBackNextLaunch() {
        let settings = freshSettings()

        // Change everything in one "launch"
        let first = CaptureManager(settings: settings)
        first.gain = 55
        first.smoothing = 0.3
        first.gravity = 0.012
        first.peakHoldTime = 90
        first.showPeaks = false

        // A new manager on the same store stands in for the next launch
        let next = CaptureManager(settings: settings)
        XCTAssertEqual(next.gain, 55)
        XCTAssertEqual(next.smoothing, 0.3)
        XCTAssertEqual(next.gravity, 0.012)
        XCTAssertEqual(next.peakHoldTime, 90)
        XCTAssertEqual(next.showPeaks, false)
    }

    func testBarCountAlwaysOpensAt16() {
        let settings = freshSettings()
        CaptureManager(settings: settings).numBars = 64
        let next = CaptureManager(settings: settings)
        XCTAssertEqual(next.numBars, 16)
        XCTAssertEqual(next.audioEngine?.numberOfBars, 16)
    }

    // Loading a setting must also reach the engine, not just the slider
    func testLoadedSettingsReachTheEngine() {
        let settings = freshSettings()
        settings.set(Float(100), forKey: SettingKeys.gain)

        // Play the same quiet tone into an engine at saved gain and one at the default
        let boosted = CaptureManager(settings: settings)
        let normal = CaptureManager(settings: freshSettings(named: "VFDVisualizerTests.normal"))
        play([1000], into: boosted.audioEngine!, amplitude: 0.002)
        play([1000], into: normal.audioEngine!, amplitude: 0.002)

        let boostedLevel = barValues(of: boosted.audioEngine!).max()!
        let normalLevel = barValues(of: normal.audioEngine!).max()!
        XCTAssertGreaterThan(boostedLevel, normalLevel + 0.2, "The saved gain of 100 should make the bars much taller")
    }

    func testResetPutsEverythingBack() {
        let settings = freshSettings()
        let manager = CaptureManager(settings: settings)
        manager.gain = 70
        manager.smoothing = 0.1
        manager.gravity = 0.02
        manager.peakHoldTime = 5
        manager.showPeaks = false
        manager.numBars = 64

        manager.resetToDefaults()

        // Back to the defaults right away
        XCTAssertEqual(manager.gain, SettingDefaults.gain)
        XCTAssertEqual(manager.smoothing, SettingDefaults.smoothing)
        XCTAssertEqual(manager.gravity, SettingDefaults.gravity)
        XCTAssertEqual(manager.peakHoldTime, SettingDefaults.peakHoldTime)
        XCTAssertEqual(manager.showPeaks, SettingDefaults.showPeaks)
        XCTAssertEqual(manager.numBars, 16)

        // And on the next launch
        let next = CaptureManager(settings: settings)
        XCTAssertEqual(next.gain, SettingDefaults.gain)
        XCTAssertEqual(next.showPeaks, SettingDefaults.showPeaks)
    }

    // The theme is saved by name, so a theme that's later removed can't break the app
    func testThemeLookupByName() {
        XCTAssertEqual(ColorTheme.named("Amber").name, "Amber")
        XCTAssertEqual(ColorTheme.named("Purple Haze").name, "Phosphor", "A removed theme falls back to the first one")
        XCTAssertEqual(SettingDefaults.themeName, ColorTheme.themes[0].name, "The default theme should be the first in the list")
    }
}
