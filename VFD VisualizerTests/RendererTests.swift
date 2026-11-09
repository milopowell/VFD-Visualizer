//
//  RendererTests.swift
//  VFD VisualizerTests
//
//  Draws through the real Renderer and shader, then reads the pixels.
//

import XCTest
import MetalKit
@testable import VFD_Visualizer

@MainActor
final class RendererTests: XCTestCase {
    private let width = 1024
    private let height = 480

    // Draws one frame and returns its pixels, top row first, 4 bytes per pixel (BGRA)
    private func drawFrame(_ manager: CaptureManager) throws -> [UInt8] {
        let renderer = Renderer(captureManager: manager, theme: ColorTheme.themes[0])
        XCTAssertNotNil(renderer.pipelineState, "The shader should load")

        // An offscreen view, set up the same way the app sets one up
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: width, height: height), device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: width, height: height)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = renderer

        Thread.sleep(forTimeInterval: 0.03) // Past the renderer's frame limiter
        let texture = try XCTUnwrap(view.currentDrawable?.texture)
        view.draw()
        spinRunLoop(for: 0.15)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // Counts the separate lit bars across the row at 25% height, the middle of a segment
    private func barsDrawn(capacity: Int32, setting: Int) throws -> Int {
        let manager = CaptureManager(barCapacity: capacity)
        let engine = try XCTUnwrap(manager.audioEngine)
        manager.numBars = setting
        for i in 0..<Int(capacity) {
            engine.frequencyBuffer[i] = 0.5
            engine.peakBuffer[i] = 0
        }

        let pixels = try drawFrame(manager)
        let row = (height * 3 / 4) * width * 4
        var runs = 0
        var inRun = false
        for x in 0..<width {
            let lit = pixels[row + x * 4 + 1] > 50
            if lit && !inRun { runs += 1 }
            inRun = lit
        }
        return runs
    }

    // Returns the lit rows down the middle of the first bar, between 35% and 65% height
    private func peakCapRows(showPeaks: Bool) throws -> [Int] {
        let manager = CaptureManager()
        let engine = try XCTUnwrap(manager.audioEngine)
        manager.showPeaks = showPeaks
        for i in 0..<16 {
            engine.frequencyBuffer[i] = 0 // No bar, so only the cap can light this area
            engine.peakBuffer[i] = 0.5
        }

        let pixels = try drawFrame(manager)
        let x = width / 16 / 2
        return (Int(Double(height) * 0.35)..<Int(Double(height) * 0.65)).filter { y in
            let p = (y * width + x) * 4
            return max(pixels[p], pixels[p + 1], pixels[p + 2]) > 120
        }
    }

    // Counts the brightly lit rows down the middle of the first bar, with no peak caps
    private func litBarRows(level: Float) throws -> Int {
        let manager = CaptureManager()
        let engine = try XCTUnwrap(manager.audioEngine)
        for i in 0..<16 {
            engine.frequencyBuffer[i] = level
            engine.peakBuffer[i] = 0
        }

        let pixels = try drawFrame(manager)
        let x = width / 16 / 2
        return (0..<height).filter { y in pixels[(y * width + x) * 4 + 1] > 150 }.count
    }

    // Bars light whole segments only, so they line up with the peak caps. A level 40% of
    // the way into a segment should look exactly like the segment below it, and 60% of
    // the way should look exactly like the next one up, with no part-lit segment.
    func testBarsLightWholeSegmentsOnly() throws {
        XCTAssertEqual(try litBarRows(level: 15.4 / 30), try litBarRows(level: 15 / 30))
        XCTAssertEqual(try litBarRows(level: 15.6 / 30), try litBarRows(level: 16 / 30))
        XCTAssertGreaterThan(try litBarRows(level: 16 / 30), try litBarRows(level: 15 / 30))
    }

    func testEachBarCountSettingDrawsThatManyBars() throws {
        for setting in [16, 32, 64] {
            XCTAssertEqual(try barsDrawn(capacity: 64, setting: setting), setting)
        }
    }

    // The settings offer 64 bars regardless of capacity. A smaller engine must limit what
    // is drawn, or the renderer and shader read past the end of its buffers.
    func testSmallerEngineLimitsTheBarsDrawn() throws {
        for setting in [16, 32, 64] {
            XCTAssertEqual(try barsDrawn(capacity: 16, setting: setting), 16, "Setting \(setting)")
        }
    }

    // A peak cap should light exactly one segment: 80% of a row of the 30-row grid,
    // since the other 20% is the gap between segments
    func testPeakCapFillsOneSegment() throws {
        let rows = try peakCapRows(showPeaks: true)
        let segment = Double(height) / 30
        XCTAssertEqual(Double(rows.count), segment * 0.8, accuracy: 2, "A thin line would light far fewer rows")
        XCTAssertEqual(rows.last.map { $0 - rows.first! + 1 }, rows.count, "The cap should be one unbroken segment")
    }

    func testPeakCapsCanBeTurnedOff() throws {
        XCTAssertEqual(try peakCapRows(showPeaks: false).count, 0)
    }
}
