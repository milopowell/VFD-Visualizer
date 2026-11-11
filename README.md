<img src="VFD%20Visualizer/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="VFD Visualizer app icon">

# VFD Visualizer

A macOS audio spectrum visualizer styled after the glowing segmented meters of vacuum fluorescent displays (VFDs) on vintage hi-fi equipment. It reacts to whatever your Mac is playing, using a C++ FFT engine and a Metal shader.

## Demo

Click the image to watch a video demonstration. The video shows an earlier version of the app.

[![Watch the demo](https://img.youtube.com/vi/0SwhqOQ5bJc/maxresdefault.jpg)](https://youtu.be/0SwhqOQ5bJc)

## Features

- Captures all system audio with a Core Audio tap, without any screen access
- 16, 32, or 64 log-spaced bars covering 40 Hz to 20 kHz
- Falling peak caps and a VFD-style glow
- Dot-matrix labels, like the character cells on a VFD panel, covering Latin and Cyrillic letters
- A standby look while offline, with only the bottom row faintly lit
- Seven color themes: Phosphor, Classic VFD, Amber, Matrix, Deep Ocean, Sunset, and Fire
- Adjustable gain, smoothing, peak gravity, and peak hold
- Optional frequency axis, bezel frame, and CPU usage readout

## Requirements

- macOS 15.6 or later
- Xcode, to build it from source

There are no third-party dependencies. The app is developed and tested on macOS 26.4 with Xcode 26.6.

## Build and run

Clone the repository and open the project:

```bash
git clone https://github.com/milopowell/VFD-Visualizer.git
```

```bash
open "VFD-Visualizer/VFD Visualizer.xcodeproj"
```

The project is set up to sign with the author's Apple developer team, so select your own team under Signing & Capabilities. Then press Cmd+R.

Debug builds use their own bundle ID and appear as VFD Visualizer (Debug), so they're never confused with an installed copy. They need their own System Audio Recording permission. To use the app day to day, build the Release configuration and copy VFD Visualizer.app into Applications.

## Usage

1. Click `OFFLINE` in the top-left corner to start capturing.
2. Allow access when macOS asks. The app appears in System Settings under Privacy & Security > Screen & System Audio Recording, in the System Audio Recording Only list.
3. Play some audio. Click `SYSTEM ACTIVE` to stop capturing.

Open the settings with the slider button in the top-right corner.

| Setting | Range | Default |
|---|---|---|
| Gain | 1 to 100 | 20 |
| Smoothing | 0 to 0.99 | 0.70 |
| Peak Gravity | 0.001 to 0.02 | 0.005 |
| Peak Hold | 0 to 120 frames | 30 frames |
| Bar Count | 16, 32, or 64 | 16 |
| Color Theme | Seven themes | Phosphor |
| Show Frequency Axis | On or off | On |
| Show Bezel Frame | On or off | On |
| Show Falling Peaks | On or off | On |
| Show CPU Usage | On or off | Off |

Settings are remembered between launches, except Bar Count, which always starts at 16. Reset to Defaults, next to Done, puts every setting back.

### If the bars don't move

If no sound has arrived after 5 seconds, the app shows a hint with an Open Settings button. macOS gives no error when the permission is off, only silence, so check that VFD Visualizer is allowed under System Audio Recording Only and that something is playing.

## How it works

```
System audio
     |
     v
Core Audio tap              Records everything except this app
     |
     v
Mono downmix                Averages the channels
     |
     v
FFT and bar mapping         4096-point FFT with a Hann window, grouped into
     |                      log-spaced bars with smoothing and peak tracking
     v
Metal fragment shader       Draws the segments, peak caps, and glow
```

| File | Role |
|---|---|
| [`CaptureManager.swift`](CaptureManager.swift) | Runs the audio tap, downmixes to mono, and tracks capture state |
| [`DSPEngine.mm`](DSPEngine.mm) | Runs the FFT and calculates the bar and peak values |
| [`DSPEngineWrapper.mm`](DSPEngineWrapper.mm) | Connects the C++ engine to Swift |
| [`Renderer.swift`](Renderer.swift) | Sends the bar values to the GPU each frame |
| [`VFDShaders.metal`](VFDShaders.metal) | Draws the display |
| [`ContentView.swift`](VFD%20Visualizer/ContentView.swift) | Provides the main window, settings, themes, and frequency axis |

## Known limitations

- Below about 100 Hz, the FFT's 11.7 Hz resolution is coarser than the bars, so neighboring bars can look alike at the 64-bar setting.
- Averaging to mono means audio that is exactly out of phase between channels cancels out.
- Output devices that aren't at 48 kHz are supported, but they've only been tested with simulated audio.

## Tests

Press Cmd+U in Xcode to run the test suite. The tests never start capturing, so they don't need the System Audio Recording permission. They do need a Mac with an audio output device.

To run them from the command line, quit the app first, because `xcodebuild` can hang after the tests finish if a copy is open:

```bash
xcodebuild test -project "VFD Visualizer.xcodeproj" -scheme "VFD Visualizer" -destination "platform=macOS"
```

## License

Released under the [MIT License](LICENSE).
