//
//  DotMatrixTextTests.swift
//  VFD VisualizerTests
//

import XCTest
import SwiftUI
@testable import VFD_Visualizer

@MainActor
final class DotMatrixTextTests: XCTestCase {
    // Every character the app draws in dots must have a shape, or it would show as a blank
    func testEveryLabelCharacterHasAGlyph() {
        let axis = FrequencyAxisView(theme: ColorTheme.themes[0])
        let labels = axis.ticks.map(\.label) + ["OFFLINE", "SYSTEM ACTIVE", "0123456789.%"]
        for label in labels {
            for character in label {
                XCTAssertNotNil(DotMatrixText.glyphs[character], "No dot shape for \"\(character)\" in \(label)")
            }
        }
    }

    func testEveryGlyphIsFiveBySeven() {
        for (character, rows) in DotMatrixText.glyphs {
            XCTAssertEqual(rows.count, 7, "\"\(character)\"")
            for row in rows {
                XCTAssertEqual(row.count, 5, "\"\(character)\"")
                XCTAssertTrue(row.allSatisfy { $0 == "0" || $0 == "1" }, "\"\(character)\"")
            }
        }
    }

    func testUnknownCharactersAreBlank() {
        XCTAssertEqual(DotMatrixText.glyph(for: "?"), DotMatrixText.blank)
    }

    // 6 dots per character, less the space after the last one, and 7 dots tall
    func testSize() {
        XCTAssertEqual(DotMatrixText.size(of: "OFFLINE", pitch: 2), CGSize(width: 82, height: 14))
        XCTAssertEqual(DotMatrixText.size(of: "", pitch: 2).width, 0)
    }

    // Draw two characters large and check every dot position against the shapes
    func testDrawsTheRightDots() throws {
        let pitch: CGFloat = 10
        let text = "1k"
        let renderer = ImageRenderer(content: DotMatrixText(text: text, color: .white, pitch: pitch).background(Color.black))
        renderer.scale = 1
        let image = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))

        for (index, character) in text.enumerated() {
            for (row, bits) in DotMatrixText.glyph(for: character).enumerated() {
                for (column, bit) in bits.enumerated() {
                    // The center of this dot's cell
                    let x = Int((CGFloat(index * 6 + column) + 0.5) * pitch)
                    let y = Int((CGFloat(row) + 0.5) * pitch)
                    let brightness = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
                    if bit == "1" {
                        XCTAssertGreaterThan(brightness, 0.8, "\"\(character)\" row \(row) column \(column) should be lit")
                    } else {
                        XCTAssertLessThan(brightness, 0.6, "\"\(character)\" row \(row) column \(column) should be dark")
                    }
                }
            }
        }
    }
}
