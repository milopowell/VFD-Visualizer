//
//  NowPlaying.swift
//  VFD Visualizer
//
//  Shows what's playing in Apple Music or Spotify. Both apps broadcast a message
//  whenever the track or play state changes, which a sandboxed app can receive
//  without any permission. There's no message at launch, so the strip appears
//  with the next change.
//

import SwiftUI
import Combine

// One track, as Apple Music or Spotify reports it
struct NowPlayingTrack: Equatable {
    let title: String
    let artist: String
    let isPlaying: Bool

    init(title: String, artist: String, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
    }

    // Reads a track-change broadcast. Both apps use the same keys.
    // Returns nil when there's no track, such as after playback stops.
    init?(userInfo: [AnyHashable: Any]) {
        guard let title = userInfo["Name"] as? String, !title.isEmpty else { return nil }
        self.title = title
        self.artist = userInfo["Artist"] as? String ?? ""
        self.isPlaying = (userInfo["Player State"] as? String) == "Playing"
    }

    // What the strip shows: "Artist - Title", or just the title if there's no artist
    var displayText: String {
        artist.isEmpty ? title : "\(artist) - \(title)"
    }
}

// Listens to both apps and decides which track to show
final class NowPlayingMonitor: ObservableObject {
    // The track to show, or nil when nothing is playing
    @Published private(set) var track: NowPlayingTrack?

    // How long to wait before showing a change. Skipping a track briefly reports
    // Paused, then Playing, and waiting stops the strip from flickering.
    var settleDelay: TimeInterval = 0.5

    // Each app's broadcast. Apple Music also sends a copy under an old iTunes name, which is ignored.
    static let broadcasts = ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"]

    // The playing track from each app, and the apps in the order they last started playing
    private var playing: [String: NowPlayingTrack] = [:]
    private var order: [String] = []
    private var pending: [String: DispatchWorkItem] = [:]
    private var observers: [NSObjectProtocol] = []

    // Start listening; safe to call more than once
    func start() {
        guard observers.isEmpty else { return }
        for name in Self.broadcasts {
            let observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                self?.handle(note.userInfo ?? [:], from: name)
            }
            observers.append(observer)
        }
    }

    deinit {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    // A broadcast arrived from one app: update that app's track once things settle
    func handle(_ userInfo: [AnyHashable: Any], from source: String) {
        let track = NowPlayingTrack(userInfo: userInfo)
        pending[source]?.cancel()
        let update = DispatchWorkItem { [weak self] in self?.apply(track, from: source) }
        pending[source] = update
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay, execute: update)
    }

    private func apply(_ track: NowPlayingTrack?, from source: String) {
        // Forget this app's old position in the order, then add it back if it's playing
        order.removeAll { $0 == source }
        if let track = track, track.isPlaying {
            playing[source] = track
            order.append(source)
        } else {
            playing[source] = nil
        }
        // Show whichever app most recently started playing
        self.track = order.last.flatMap { playing[$0] }
    }
}

// The Now Playing box: "Now Playing: Artist - Title", always scrolling through,
// in a small framed display that stays between a minimum and maximum width
struct NowPlayingView: View {
    let track: NowPlayingTrack
    var color: Color

    // The box takes what the header can spare, but never less or more than these
    static let minWidth: CGFloat = 200
    static let maxWidth: CGFloat = 320

    // Scrolling speed in points per second, and the gap before the text comes around again
    var speed: CGFloat = 30
    var gap: CGFloat = 48

    // Distance between dot centers, matching the status label
    private let pitch: CGFloat = 1.75

    // The words in the box
    static func label(for track: NowPlayingTrack) -> String {
        "Now Playing: \(track.displayText)"
    }

    var body: some View {
        let text = NowPlayingView.label(for: track)
        // Dots when every character has a shape, otherwise the system font
        let usesDots = DotMatrixText.canDraw(text)
        let dotSize = DotMatrixText.size(of: text, pitch: pitch, reservesDescenders: true)
        let textWidth = usesDots ? dotSize.width : NowPlayingView.systemFontWidth(of: text)

        // Two copies side by side, always moving left, so the text loops without a jump
        TimelineView(.animation) { context in
            let offset = NowPlayingView.scrollOffset(seconds: context.date.timeIntervalSinceReferenceDate, cycle: textWidth + gap, speed: speed)
            // Measure the space inside the box, so the text is clipped to exactly that
            GeometryReader { space in
                HStack(spacing: gap) {
                    copy(of: text, usesDots: usesDots)
                    copy(of: text, usesDots: usesDots)
                }
                .fixedSize()
                .offset(x: -offset)
                .frame(width: space.size.width, height: space.size.height, alignment: .leading)
                .clipped()
            }
        }
        .frame(height: dotSize.height)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth)
        // Nothing scrolls outside the box
        .clipped()
        // A small framed display, like a separate readout on the panel
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.3), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    // One copy of the scrolling text
    @ViewBuilder private func copy(of text: String, usesDots: Bool) -> some View {
        if usesDots {
            DotMatrixText(text: text, color: color, pitch: pitch, reservesDescenders: true)
        } else {
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .fixedSize()
        }
    }

    // How far the text has scrolled at a given time, wrapping around once per cycle
    static func scrollOffset(seconds: TimeInterval, cycle: CGFloat, speed: CGFloat) -> CGFloat {
        guard cycle > 0, speed > 0 else { return 0 }
        return CGFloat(seconds.truncatingRemainder(dividingBy: Double(cycle / speed))) * speed
    }

    // Width of text in the system font fallback, so it scrolls the same way
    static func systemFontWidth(of text: String) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
}
