//
//  FrequencyAxisTests.swift
//  VFD VisualizerTests
//

import XCTest
import SwiftUI
@testable import VFD_Visualizer

@MainActor
final class FrequencyAxisTests: XCTestCase {
    private let axis = FrequencyAxisView(theme: ColorTheme.themes[0])

    func testLabelSet() {
        XCTAssertEqual(axis.ticks.map(\.label), ["50Hz", "100Hz", "500Hz", "1kHz", "5kHz", "10kHz"])
    }

    func testScaleMatchesTheBarRange() {
        XCTAssertEqual(axis.position(of: VFD_MIN_FREQUENCY), 0, accuracy: 1e-5)
        XCTAssertEqual(axis.position(of: VFD_MAX_FREQUENCY), 1, accuracy: 1e-5)
    }

    // Each label should sit on the bar its frequency lights. One bar of slack allows for
    // the low end, where FFT bins are wider than bars and a tone can land between two.
    func testLabelsSitOnTheBarsTheirFrequenciesLight() {
        let bars = 64.0
        for tick in axis.ticks {
            let engine = makeEngine(bars: 64)
            play([Double(tick.hz)], into: engine)
            let lit = Double(loudestBar(of: engine))
            let position = Double(axis.position(of: tick.hz))
            XCTAssertGreaterThanOrEqual(position, (lit - 1) / bars, tick.label)
            XCTAssertLessThanOrEqual(position, (lit + 2) / bars, tick.label)
        }
    }

    // Measures the real rendered view, because a layout bug once shifted every label
    // while the position calculations stayed correct.
    func testRenderedLabelsAreCenteredAndInFrame() throws {
        for width in [760.0, 800.0, 1248.0] {
            let renderer = ImageRenderer(content: axis.frame(width: width, height: 30).background(Color.black))
            renderer.scale = 2
            let image = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))

            var runs: [(start: Double, end: Double)] = []
            var start: Int?
            var last = -100
            for x in 0..<image.pixelsWide {
                let lit = (0..<image.pixelsHigh).contains { y in
                    (image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.greenComponent ?? 0) > 0.4
                }
                guard lit else { continue }
                if let first = start, x - last > 16 {
                    runs.append((Double(first) / 2, Double(last + 1) / 2))
                    start = x
                } else if start == nil {
                    start = x
                }
                last = x
            }
            if let first = start { runs.append((Double(first) / 2, Double(last + 1) / 2)) }

            XCTAssertEqual(runs.count, axis.ticks.count, "Width \(width)")
            guard runs.count == axis.ticks.count else { continue }
            for (tick, run) in zip(axis.ticks, runs) {
                let target = axis.position(of: tick.hz) * width
                XCTAssertGreaterThanOrEqual(run.start, 0, tick.label)
                XCTAssertLessThanOrEqual(run.end, width, tick.label)
                XCTAssertEqual((run.start + run.end) / 2, target, accuracy: 2, "\(tick.label) at width \(width)")
            }
        }
    }
}
