//
//  RendererTests.swift
//  VFD VisualizerTests
//
//  Draws through the real Renderer and shader, then counts the bars in the pixels.
//

import XCTest
import MetalKit
@testable import VFD_Visualizer

final class RendererTests: XCTestCase {
    private let width = 1024
    private let height = 240

    private func barsDrawn(capacity: Int32, setting: Int) throws -> Int {
        let manager = CaptureManager(barCapacity: capacity)
        let engine = try XCTUnwrap(manager.audioEngine)
        let renderer = Renderer(captureManager: manager, theme: ColorTheme.themes[0])
        XCTAssertNotNil(renderer.pipelineState, "The shader should load")

        let view = MTKView(frame: NSRect(x: 0, y: 0, width: width, height: height), device: MTLCreateSystemDefaultDevice())
        view.framebufferOnly = false
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: width, height: height)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = renderer

        manager.numBars = setting
        for i in 0..<Int(capacity) {
            engine.frequencyBuffer[i] = 0.5
            engine.peakBuffer[i] = 0
        }

        Thread.sleep(forTimeInterval: 0.03) // Past the renderer's frame limiter
        let texture = try XCTUnwrap(view.currentDrawable?.texture)
        view.draw()
        spinRunLoop(for: 0.15)

        // The row at 25% height runs through the middle of a segment
        var row = [UInt8](repeating: 0, count: width * 4)
        texture.getBytes(&row, bytesPerRow: width * 4, from: MTLRegionMake2D(0, height * 3 / 4, width, 1), mipmapLevel: 0)
        var runs = 0
        var inRun = false
        for x in 0..<width {
            let lit = row[x * 4 + 1] > 50
            if lit && !inRun { runs += 1 }
            inRun = lit
        }
        return runs
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
}
