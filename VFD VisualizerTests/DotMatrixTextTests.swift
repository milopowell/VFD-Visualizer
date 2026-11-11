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

    // 5 dots wide and 7 rows tall, plus 2 rows below the line only for letters with a tail there
    func testEveryGlyphIsFiveBySeven() {
        for (character, rows) in DotMatrixText.glyphs {
            XCTAssertTrue(rows.count == 7 || rows.count == 9, "\"\(character)\" has \(rows.count) rows")
            if rows.count == 9 {
                XCTAssertTrue(rows[7...].contains { $0.contains("1") }, "\"\(character)\" has empty rows below the line")
            }
            for row in rows {
                XCTAssertEqual(row.count, 5, "\"\(character)\"")
                XCTAssertTrue(row.allSatisfy { $0 == "0" || $0 == "1" }, "\"\(character)\"")
            }
        }
    }

    func testUnknownCharactersAreBlank() {
        XCTAssertEqual(DotMatrixText.glyph(for: "龍"), DotMatrixText.blank)
    }

    // Song titles can use anything you can type, so every printable ASCII character needs a shape
    func testEveryPrintableASCIICharacterHasAGlyph() {
        for code in 32...126 {
            let character = Character(UnicodeScalar(code)!)
            XCTAssertNotNil(DotMatrixText.glyphs[character], "No dot shape for \"\(character)\"")
        }
    }

    // Accents are dropped and typographic marks simplified, as on hardware displays
    func testAccentsAndTypographicMarksAreSimplified() {
        XCTAssertEqual(DotMatrixText.normalized("João Gilberto – Chega De Saudade"), "Joao Gilberto - Chega De Saudade")
        XCTAssertEqual(DotMatrixText.normalized("Don’t Stop…"), "Don't Stop...")
        XCTAssertTrue(DotMatrixText.canDraw("Antônio Carlos Jobim & Vinicius De Moraes"))
    }

    // Every letter of the Russian, Ukrainian, Belarusian, and Serbian alphabets has a shape
    func testEveryCyrillicLetterHasAGlyph() {
        let alphabets = [
            "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ", "абвгдеёжзийклмнопрстуфхцчшщъыьэюя",
            "ЄІЇҐєіїґ", "Ўў", "ЂЋЉЊЏЈЅђћљњџјѕ",
        ]
        for alphabet in alphabets {
            for character in alphabet {
                XCTAssertNotNil(DotMatrixText.glyphs[character], "No dot shape for \"\(character)\"")
            }
        }
    }

    // Cyrillic letters that look like Latin ones use exactly the same dots
    func testLookalikeCyrillicLettersShareLatinShapes() {
        for (cyrillic, latin) in DotMatrixText.cyrillicSameAsLatin {
            XCTAssertEqual(DotMatrixText.glyphs[cyrillic], DotMatrixText.latinGlyphs[latin], "\"\(cyrillic)\"")
        }
    }

    // Й is a separate letter from И, not И with an accent, so it keeps its mark. The same
    // holds when a title stores it as И plus a separate breve mark.
    func testCyrillicLettersKeepTheirMarks() {
        XCTAssertEqual(DotMatrixText.normalized("Ёлка и Йогурт"), "Ёлка и Йогурт")
        XCTAssertEqual(DotMatrixText.normalized("И\u{0306}"), "Й")
        XCTAssertNotEqual(DotMatrixText.glyph(for: "Й"), DotMatrixText.glyph(for: "И"))
        XCTAssertTrue(DotMatrixText.canDraw("Кино - Группа крови"))
        XCTAssertTrue(DotMatrixText.canDraw("Океан Ельзи - Обійми"))
    }

    // Text that can't be drawn in dots falls back to the system font
    func testTextWithoutDotShapesIsDetected() {
        XCTAssertFalse(DotMatrixText.canDraw("坂本龍一"))
        XCTAssertFalse(DotMatrixText.canDraw("Sigur Rós - Ágætis byrjun"), "æ isn't an accented letter, so it has no shape")
    }

    // Text with tails below the line is two rows taller, unless room is always reserved
    func testDescendersAddTwoRows() {
        XCTAssertEqual(DotMatrixText.size(of: "SONG", pitch: 1).height, 7)
        XCTAssertEqual(DotMatrixText.size(of: "Song", pitch: 1).height, 9)
        XCTAssertEqual(DotMatrixText.size(of: "SONG", pitch: 1, reservesDescenders: true).height, 9)
    }

    // Sizes follow the simplified text, so an ellipsis takes three characters of space
    func testSizeUsesTheSimplifiedText() {
        XCTAssertEqual(DotMatrixText.size(of: "A…", pitch: 1), DotMatrixText.size(of: "A...", pitch: 1))
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
