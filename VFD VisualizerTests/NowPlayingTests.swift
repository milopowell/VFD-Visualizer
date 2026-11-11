//
//  NowPlayingTests.swift
//  VFD VisualizerTests
//
//  Messages here are copied from what Apple Music really sent during a test on 2026-11-11.
//

import XCTest
import Combine
import SwiftUI
@testable import VFD_Visualizer

final class NowPlayingTests: XCTestCase {
    private let music = "com.apple.Music.playerInfo"
    private let spotify = "com.spotify.client.PlaybackStateChanged"

    // Apple Music's message for a playing track
    private let playing: [AnyHashable: Any] = [
        "Name": "Autumn Sweater", "Artist": "Yo La Tengo", "Album": "I Can Hear the Heart Beating As One",
        "Player State": "Playing", "Genre": "Alternative", "Total Time": 318421,
    ]

    private func makeMonitor() -> NowPlayingMonitor {
        let monitor = NowPlayingMonitor()
        monitor.settleDelay = 0.1
        return monitor
    }

    private func with(_ info: [AnyHashable: Any], _ changes: [AnyHashable: Any]) -> [AnyHashable: Any] {
        info.merging(changes) { _, new in new }
    }

    // MARK: Reading messages

    func testReadsAppleMusicsMessage() {
        let track = NowPlayingTrack(userInfo: playing)
        XCTAssertEqual(track, NowPlayingTrack(title: "Autumn Sweater", artist: "Yo La Tengo", isPlaying: true))
        XCTAssertEqual(track?.displayText, "Yo La Tengo - Autumn Sweater")
    }

    func testPausedTrackIsNotPlaying() {
        XCTAssertEqual(NowPlayingTrack(userInfo: with(playing, ["Player State": "Paused"]))?.isPlaying, false)
    }

    func testMessageWithoutATrackIsIgnored() {
        // After playback stops, the message can arrive with only the state
        XCTAssertNil(NowPlayingTrack(userInfo: ["Player State": "Stopped"]))
    }

    func testTitleOnlyWhenThereIsNoArtist() {
        XCTAssertEqual(NowPlayingTrack(title: "Chega De Saudade", artist: "", isPlaying: true).displayText, "Chega De Saudade")
    }

    // MARK: Deciding what to show

    func testPlayingTrackAppearsAfterSettling() {
        let monitor = makeMonitor()
        monitor.handle(playing, from: music)
        XCTAssertNil(monitor.track, "Changes wait to settle")
        spinRunLoop(for: 0.3)
        XCTAssertEqual(monitor.track?.title, "Autumn Sweater")
    }

    func testPausingHidesTheStrip() {
        let monitor = makeMonitor()
        monitor.handle(playing, from: music)
        spinRunLoop(for: 0.3)
        monitor.handle(with(playing, ["Player State": "Paused"]), from: music)
        spinRunLoop(for: 0.3)
        XCTAssertNil(monitor.track)
    }

    // Skipping sends Paused for the old track, then Playing for the new one, within a moment
    func testSkippingDoesNotFlicker() {
        let monitor = makeMonitor()
        monitor.handle(playing, from: music)
        spinRunLoop(for: 0.3)

        var shown: [String?] = []
        let watcher = monitor.$track.sink { shown.append($0?.title) }
        monitor.handle(with(playing, ["Player State": "Paused"]), from: music)
        monitor.handle(["Name": "Always Something There to Remind Me", "Artist": "Naked Eyes", "Player State": "Paused"], from: music)
        monitor.handle(["Name": "Always Something There to Remind Me", "Artist": "Naked Eyes", "Player State": "Playing"], from: music)
        spinRunLoop(for: 0.3)
        watcher.cancel()

        XCTAssertFalse(shown.dropFirst().contains(nil), "The strip should never disappear during a skip")
        XCTAssertEqual(monitor.track?.title, "Always Something There to Remind Me")
    }

    // If both apps play, show the one that started most recently, and fall back when it pauses
    func testMostRecentlyStartedAppWins() {
        let monitor = makeMonitor()
        monitor.handle(playing, from: music)
        spinRunLoop(for: 0.3)
        monitor.handle(["Name": "Song From Spotify", "Artist": "Someone", "Player State": "Playing"], from: spotify)
        spinRunLoop(for: 0.3)
        XCTAssertEqual(monitor.track?.title, "Song From Spotify")

        monitor.handle(["Name": "Song From Spotify", "Artist": "Someone", "Player State": "Paused"], from: spotify)
        spinRunLoop(for: 0.3)
        XCTAssertEqual(monitor.track?.title, "Autumn Sweater", "Apple Music is still playing")
    }

    // MARK: The Now Playing box

    func testBoxReadsNowPlaying() {
        let track = NowPlayingTrack(title: "Autumn Sweater", artist: "Yo La Tengo", isPlaying: true)
        XCTAssertEqual(NowPlayingView.label(for: track), "Now Playing: Yo La Tengo - Autumn Sweater")
    }

    // Even a short title keeps moving, and wraps around after one full cycle
    func testTextAlwaysScrolls() {
        let cycle: CGFloat = 200
        XCTAssertEqual(NowPlayingView.scrollOffset(seconds: 0, cycle: cycle, speed: 30), 0)
        XCTAssertEqual(NowPlayingView.scrollOffset(seconds: 1, cycle: cycle, speed: 30), 30, accuracy: 0.01)
        XCTAssertEqual(NowPlayingView.scrollOffset(seconds: Double(cycle / 30) + 1, cycle: cycle, speed: 30), 30, accuracy: 0.01)
    }

    func testWidthLimitsAreSensible() {
        XCTAssertLessThan(NowPlayingView.minWidth, NowPlayingView.maxWidth)
    }

    // In a header with room to spare the box grows to its maximum, and in a tight one
    // it stays at its minimum. Measured from the real rendered box.
    @MainActor
    func testBoxStaysBetweenMinimumAndMaximumWidth() throws {
        let track = NowPlayingTrack(title: "Autumn Sweater", artist: "Yo La Tengo", isPlaying: true)
        func boxWidth(headerWidth: CGFloat) throws -> CGFloat {
            // A header with 300 pt of fixed content on the left, like the status label and window buttons
            let header = HStack(spacing: 0) {
                Color.clear.frame(width: 300)
                Spacer()
                NowPlayingView(track: track, color: .white)
                Spacer()
            }
            .frame(width: headerWidth, height: 40)
            // A wide black canvas, so a box held at its minimum is measured in full even if it overflows the header
            .frame(width: 1200, alignment: .leading)
            .background(Color.black)
            let renderer = ImageRenderer(content: header)
            renderer.scale = 1
            let image = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            // The box is the only thing drawn, so its edges are the outermost non-black columns
            let lit = (0..<image.pixelsWide).filter { x in
                (0..<image.pixelsHigh).contains { y in (image.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.02 }
            }
            return CGFloat((lit.last ?? 0) - (lit.first ?? 0) + 1)
        }
        XCTAssertEqual(try boxWidth(headerWidth: 800), NowPlayingView.maxWidth, accuracy: 3, "Room to spare: the box takes its maximum")
        XCTAssertEqual(try boxWidth(headerWidth: 450), NowPlayingView.minWidth, accuracy: 3, "Tight header: the box keeps its minimum")
    }
}
