//
//  DotMatrixText.swift
//  VFD Visualizer
//

import SwiftUI

// Draws short text as 5x7 dots, like the character cells on a VFD panel.
// Used for the status label, CPU readout, and frequency labels; longer text stays in the system font.
struct DotMatrixText: View {
    let text: String
    var color: Color
    // Distance between dot centers, in points
    var pitch: CGFloat = 1.75

    var body: some View {
        let size = DotMatrixText.size(of: text, pitch: pitch)
        Canvas { context, _ in
            // Each dot fills most of its cell, leaving a small gap between dots
            let radius = pitch * 0.38
            for (index, character) in text.enumerated() {
                for (row, bits) in DotMatrixText.glyph(for: character).enumerated() {
                    for (column, bit) in bits.enumerated() where bit == "1" {
                        // Each character is 5 dots wide, plus one dot of space before the next
                        let x = (CGFloat(index * 6 + column) + 0.5) * pitch
                        let y = (CGFloat(row) + 0.5) * pitch
                        let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: dot), with: .color(color))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        // A soft glow around the dots, like phosphor
        .shadow(color: color.opacity(0.5), radius: pitch)
        // Drawn dots aren't text to VoiceOver, so give it the words
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    // Width and height of the dots for this text
    static func size(of text: String, pitch: CGFloat) -> CGSize {
        CGSize(width: CGFloat(max(0, text.count * 6 - 1)) * pitch, height: 7 * pitch)
    }

    // The 5x7 pattern for a character, top row first. Characters without one are left blank.
    static func glyph(for character: Character) -> [String] {
        glyphs[character] ?? blank
    }

    static let blank = Array(repeating: "00000", count: 7)

    // Classic 5x7 shapes, as on character VFD and LCD panels. Each string is one row, 1 = lit.
    static let glyphs: [Character: [String]] = [
        // Status labels: OFFLINE, SYSTEM ACTIVE
        "A": ["01110", "10001", "10001", "10001", "11111", "10001", "10001"],
        "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "Y": ["10001", "10001", "10001", "01010", "00100", "00100", "00100"],
        // Frequency labels: Hz and kHz
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "k": ["10000", "10000", "10010", "10100", "11000", "10100", "10010"],
        "z": ["00000", "00000", "11111", "00010", "00100", "01000", "11111"],
        // Digits, plus the decimal point and percent sign for the CPU readout
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
        "%": ["11000", "11001", "00010", "00100", "01000", "10011", "00011"],
        " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    ]
}
