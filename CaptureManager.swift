//
//  CaptureManager.swift
//  VFD Visualizer
//
//  Created by Milo Powell on 1/16/26.
//

import Foundation
import CoreAudio
import Accelerate // Not used here, but this import is what links vDSP for DSPEngine
import Combine

// Names the settings are saved under
enum SettingKeys {
    static let gain = "gain"
    static let smoothing = "smoothing"
    static let gravity = "peakGravity"
    static let peakHoldTime = "peakHoldTime"
    static let showPeaks = "showPeaks"
    static let showFrequencyAxis = "showFrequencyAxis"
    static let showBezel = "showBezel"
    static let themeName = "themeName"
    static let showCPU = "showCPU"
}

// Default settings, used on first launch and by Reset to Defaults
enum SettingDefaults {
    static let gain: Float = 20.0
    static let smoothing: Float = 0.7
    static let gravity: Float = 0.005
    static let peakHoldTime = 30
    static let showPeaks = true
    static let numBars = 16 // Never saved, so the app always opens at 16 bars
    static let showFrequencyAxis = true
    static let showBezel = true
    static let themeName = "Phosphor"
    static let showCPU = false
}

class CaptureManager: NSObject, ObservableObject {
    
    // Audio settings: each one updates the engine and saves itself for next launch
    @Published var gain: Float = SettingDefaults.gain {
        didSet {
            audioEngine?.setGain(gain)
            settings.set(gain, forKey: SettingKeys.gain)
        }
    }
    @Published var smoothing: Float = SettingDefaults.smoothing {
        didSet {
            audioEngine?.setSmoothing(smoothing)
            settings.set(smoothing, forKey: SettingKeys.smoothing)
        }
    }
    @Published var gravity: Float = SettingDefaults.gravity {
        didSet {
            audioEngine?.setGravity(gravity)
            settings.set(gravity, forKey: SettingKeys.gravity)
        }
    }
    // Bar count isn't saved, so the app always opens at 16 bars
    @Published var numBars: Int = SettingDefaults.numBars {
        didSet { audioEngine?.setNumBars(Int32(numBars)) }
    }
    @Published var showPeaks: Bool = SettingDefaults.showPeaks {
        didSet { settings.set(showPeaks, forKey: SettingKeys.showPeaks) }
    }
    
    @Published var peakHoldTime: Int = SettingDefaults.peakHoldTime {
        didSet {
            audioEngine?.setHoldTime(Int32(peakHoldTime))
            settings.set(peakHoldTime, forKey: SettingKeys.peakHoldTime)
        }
    }

    // Where settings are saved. Tests pass their own, so they never touch the app's.
    private let settings: UserDefaults

    let audioEngine: DSPEngineWrapper?
    @Published var isRecording: Bool = false {
        didSet {
            if !isRecording {
                // Start decay when offline
                startDecay()
            } else {
                // Stop decay when online
                stopDecay()
            }
        }
    }
    
    
    // What's wrong with capture, if anything, shown next to the status indicator
    @Published var captureProblem: CaptureProblem?
    // The system audio tap, while capturing
    private var tap: SystemAudioTap?
    private var decayTimer: Timer?

    // How long to wait for any sound before suggesting that permission may be off
    var noAudioHintDelay: TimeInterval = 5
    // Whether any sound has arrived since capture started
    private var heardAudio = false
    // Counts start attempts, so a slow start can tell it has been replaced
    private var captureAttempt = 0

    // Watch the system's default output device, which changes when you switch to headphones
    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private lazy var outputDeviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.restartAfterOutputChange()
    }

    // The capacity should cover the largest bar count in settings
    init(barCapacity: Int32 = 64, settings: UserDefaults = .standard) {
        // Create the C++ engine with room for the most bars
        audioEngine = DSPEngineWrapper(size: barCapacity)
        self.settings = settings
        super.init()

        // Load the settings saved last time, falling back to the defaults
        gain = settings.object(forKey: SettingKeys.gain) as? Float ?? SettingDefaults.gain
        smoothing = settings.object(forKey: SettingKeys.smoothing) as? Float ?? SettingDefaults.smoothing
        gravity = settings.object(forKey: SettingKeys.gravity) as? Float ?? SettingDefaults.gravity
        peakHoldTime = settings.object(forKey: SettingKeys.peakHoldTime) as? Int ?? SettingDefaults.peakHoldTime
        showPeaks = settings.object(forKey: SettingKeys.showPeaks) as? Bool ?? SettingDefaults.showPeaks

        // Setting each one above runs its didSet, which passes it to the engine.
        // The bar count isn't loaded, so match the engine to the app's default here.
        audioEngine?.setNumBars(Int32(numBars)) // The engine keeps its own default, so match the app's
        // Restart capture whenever the output device changes
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, outputDeviceChanged)
    }

    deinit {
        // Stop watching the output device
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, outputDeviceChanged)
    }

    // Put every audio setting back to its default, including 16 bars, and forget the saved values
    func resetToDefaults() {
        gain = SettingDefaults.gain
        smoothing = SettingDefaults.smoothing
        gravity = SettingDefaults.gravity
        peakHoldTime = SettingDefaults.peakHoldTime
        showPeaks = SettingDefaults.showPeaks
        numBars = SettingDefaults.numBars
        for key in [SettingKeys.gain, SettingKeys.smoothing, SettingKeys.gravity, SettingKeys.peakHoldTime, SettingKeys.showPeaks] {
            settings.removeObject(forKey: key)
        }
    }

    // Stop capturing and go offline
    func stopStream() {
        captureAttempt += 1 // Cancels any start still in progress
        tap?.stop()
        tap = nil
        captureProblem = nil
        if isRecording { isRecording = false }
    }

    // Start a new attempt: clear any old message and return this attempt's number
    func beginCaptureAttempt() -> Int {
        captureAttempt += 1
        captureProblem = nil
        heardAudio = false
        return captureAttempt
    }

    // Setting up a tap takes time, so it may have been stopped or restarted by the time it's ready
    func finishCaptureAttempt(_ attempt: Int, with newTap: SystemAudioTap) {
        // A stop or a newer start happened while this tap was being set up, so discard it
        guard attempt == captureAttempt else {
            newTap.stop()
            return
        }
        // Keep the tap, go online, and start watching for silence
        tap = newTap
        isRecording = true
        watchForSilence()
    }

    // Start capturing system audio. This runs off the main thread, since setup can take a moment
    func startStream() async {
        let attempt = await MainActor.run { self.beginCaptureAttempt() }
        do {
            // Create the tap, then tell the engine the device's real sample rate
            let newTap = try SystemAudioTap()
            audioEngine?.setSampleRate(Float(newTap.sampleRate))
            print("Capturing system audio at \(newTap.sampleRate) Hz")

            // Feed each block of audio to the engine as it arrives
            var signalSeen = false // Only touched on the tap's queue
            try newTap.start { [weak self] samples in
                guard let self = self else { return }
                // Pass to C++ Engine
                self.audioEngine?.processAudioSamples(samples.baseAddress, count: Int32(samples.count))
                // The first block with any sound in it clears the silence hint
                if !signalSeen && samples.contains(where: { $0 != 0 }) {
                    signalSeen = true
                    DispatchQueue.main.async { self.audioDetected() }
                }
            }

            // Back on the main thread, go online unless this attempt was replaced
            await MainActor.run { self.finishCaptureAttempt(attempt, with: newTap) }
        } catch {
            await MainActor.run {
                // Only report failures from the current attempt
                if attempt == self.captureAttempt { self.handleCaptureFailure(error) }
            }
        }
    }

    // A denied tap delivers silence rather than an error, and Core Audio has no public way
    // to ask for the permission's state, so a long silence is the only available signal.
    func watchForSilence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + noAudioHintDelay) { [weak self] in
            guard let self = self, self.isRecording, !self.heardAudio else { return }
            self.captureProblem = .noAudioYet
        }
    }

    // Sound has arrived: clear the silence hint, but keep any real failure message
    func audioDetected() {
        heardAudio = true
        if captureProblem == .noAudioYet { captureProblem = nil }
    }

    // Single path for every capture failure: go offline and tell the user why
    func handleCaptureFailure(_ error: Error) {
        print("Capture failed: \(error)")
        tap?.stop()
        tap = nil
        captureProblem = .failed(error.localizedDescription)
        if isRecording { isRecording = false }
    }

    // The tap is tied to the output device, so follow the system when it changes
    private func restartAfterOutputChange() {
        // Only restart if capture was running, then replace the old tap with a new one
        guard isRecording else { return }
        tap?.stop()
        tap = nil
        Task { await startStream() }
    }

    // Decay animation
    private func startDecay() {
        // Run decay at 60fps
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in self?.applyDecay()
        }
    }
    
    private func stopDecay() {
        decayTimer?.invalidate()
        decayTimer = nil
    }
    
    private func applyDecay() {
        guard let engine = audioEngine,
        let freqPtr = engine.frequencyBuffer,
        let peakPtr = engine.peakBuffer else { return }

        let count = Int(engine.numberOfBars)
        
        // Decay frequency bars
        for i in 0..<count {
            if freqPtr[i] > 0 {
                freqPtr[i] -= Float(gravity) * 2.0 // Decay rate
                if freqPtr[i] < 0 { freqPtr[i] = 0 }
            }
        }
        
        // Decay peaks
        for i in 0..<count {
            if peakPtr[i] > 0 {
                peakPtr[i] -= Float(gravity)
                if peakPtr[i] < 0 { peakPtr[i] = 0 }
            }
        }
    }
}

// Why capture isn't working, in terms the user can act on
enum CaptureProblem: Equatable {
    // Capturing, but no sound has arrived, which often means the permission is off
    case noAudioYet
    // Capture stopped, with the reason Core Audio gave
    case failed(String)

    // The text shown in the app
    var message: String {
        switch self {
        case .noAudioYet: return "No audio detected. If something is playing, allow this app under System Audio Recording Only."
        case .failed(let reason): return "Capture stopped: \(reason)"
        }
    }
}

// A Core Audio call failed: which step it was, and the error code it returned
struct CoreAudioError: LocalizedError {
    let step: String
    let status: OSStatus

    var errorDescription: String? { "\(step) (Core Audio error \(status))." }
}

// Turns a Core Audio status code into a thrown error
private func check(_ status: OSStatus, _ step: String) throws {
    guard status == noErr else { throw CoreAudioError(step: step, status: status) }
}

// Reads one property from a Core Audio object, such as a device's ID or the tap's format
private func audioProperty<T>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T, qualifierSize: UInt32 = 0, qualifier: UnsafeRawPointer? = nil, step: String) throws -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, qualifierSize, qualifier, &size, $0)
    }
    try check(status, step)
    return value
}

// The FFT reads 32-bit floats, and needs a real sample rate to place its bars
func isSupportedTapFormat(_ format: AudioStreamBasicDescription) -> Bool {
    format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 && format.mSampleRate > 0
}

// Records everything the system plays, except this app, without any screen access.
// A process tap can only be read through an aggregate device that contains it.
final class SystemAudioTap {
    // The device's sample rate, read when the tap is created
    private(set) var sampleRate: Double = 0
    // Core Audio IDs for the tap, the device that reads it, and the audio callback
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    // Audio arrives on this queue, off the main thread
    private let queue = DispatchQueue(label: "VFDVisualizer.SystemAudioTap", qos: .userInteractive)

    // Set up the tap, cleaning up anything half-created if a step fails
    init() throws {
        do {
            try create()
        } catch {
            stop()
            throw error
        }
    }

    deinit { stop() }

    private func create() throws {
        let system = AudioObjectID(kAudioObjectSystemObject)

        // Find this app's own process, so the tap can leave out its sound
        var pid = ProcessInfo.processInfo.processIdentifier
        let ownProcess: AudioObjectID = try audioProperty(of: system, kAudioHardwarePropertyTranslatePIDToProcessObject, initial: AudioObjectID(kAudioObjectUnknown), qualifierSize: UInt32(MemoryLayout<pid_t>.size), qualifier: &pid, step: "Couldn't identify this app to Core Audio")

        // Describe the tap: a stereo mix of all system audio except this app, hidden from other apps
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        description.uuid = UUID()
        description.name = "VFD Visualizer"
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Couldn't create the system audio tap")

        // Read the tap's audio format and make sure the engine can use it
        let format: AudioStreamBasicDescription = try audioProperty(of: tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription(), step: "Couldn't read the audio format")
        guard isSupportedTapFormat(format) else {
            throw CoreAudioError(step: "The system audio format isn't supported", status: OSStatus(format.mFormatID))
        }
        sampleRate = format.mSampleRate

        // The capture device runs on the output device's clock, so look up its ID
        let outputDevice: AudioObjectID = try audioProperty(of: system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown), step: "Couldn't find the output device")
        let outputUID: Unmanaged<CFString>? = try audioProperty(of: outputDevice, kAudioDevicePropertyDeviceUID, initial: nil, step: "Couldn't identify the output device")
        guard let outputUID = outputUID?.takeRetainedValue() as String? else {
            throw CoreAudioError(step: "Couldn't identify the output device", status: kAudioHardwareUnspecifiedError)
        }

        // Build a private aggregate device that contains the tap; it's the only way to read a tap
        let device: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VFD Visualizer Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]]
        ]
        try check(AudioHardwareCreateAggregateDevice(device as CFDictionary, &deviceID), "Couldn't create the capture device")
    }

    // Start delivering audio. Each block is mixed down to mono before it reaches onSamples
    func start(onSamples: @escaping (UnsafeMutableBufferPointer<Float>) -> Void) throws {
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in
            withMonoSamples(in: input, body: onSamples)
        }, "Couldn't connect to the capture device")
        try check(AudioDeviceStart(deviceID, procID), "Couldn't start capturing audio")
    }

    // Safe to call repeatedly, and after a partly failed setup
    func stop() {
        // Stop the audio callback
        if let procID = procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        // Remove the capture device
        if deviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        // Remove the tap
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}

// Calls `body` with one mono channel of audio. The FFT needs a single continuous
// signal, so the channels are averaged whether they arrive planar (one buffer per
// channel) or interleaved (one buffer of LRLR...).
func withMonoSamples(in bufferList: UnsafePointer<AudioBufferList>, body: (UnsafeMutableBufferPointer<Float>) -> Void) {
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))

    // Work out how many frames this block holds
    var frameCount = 0
    for buffer in buffers where buffer.mData != nil && buffer.mNumberChannels > 0 {
        frameCount = max(frameCount, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels)))
    }
    guard frameCount > 0 else { return }

    // Average the channels into a temporary mono buffer, without allocating memory for each block
    withUnsafeTemporaryAllocation(of: Float.self, capacity: frameCount) { mono in
        mono.initialize(repeating: 0)
        var totalChannels = 0

        for buffer in buffers {
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let channels = Int(buffer.mNumberChannels)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)

            // Add up the channels in this buffer
            for frame in 0..<frames {
                for channel in 0..<channels {
                    mono[frame] += samples[frame * channels + channel]
                }
            }
            totalChannels += channels
        }

        // Divide by the channel count to get the average
        for frame in 0..<frameCount {
            mono[frame] /= Float(totalChannels)
        }
        // Hand the mono audio to the caller
        body(mono)
    }
}
