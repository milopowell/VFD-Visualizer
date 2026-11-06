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

class CaptureManager: NSObject, ObservableObject {
    
    @Published var gain: Float = 20.0 {
        didSet { audioEngine?.setGain(gain) }
    }
    @Published var smoothing: Float = 0.7 {
        didSet { audioEngine?.setSmoothing(smoothing) }
    }
    @Published var gravity: Float = 0.005 {
        didSet { audioEngine?.setGravity(gravity) }
    }
    @Published var numBars: Int = 32 {
        didSet { audioEngine?.setNumBars(Int32(numBars)) }
    }
    @Published var showPeaks: Bool = true
    
    @Published var peakHoldTime: Int = 30 {
        didSet { audioEngine?.setHoldTime(Int32(peakHoldTime)) }
    }

    let audioEngine = DSPEngineWrapper(size: 64) // Should cover the largest bar count in settings
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
    
    
    @Published var captureProblem: CaptureProblem?
    private var tap: SystemAudioTap?
    private var decayTimer: Timer?

    // How long to wait for any sound before suggesting that permission may be off
    var noAudioHintDelay: TimeInterval = 5
    private var heardAudio = false

    private var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private lazy var outputDeviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.restartAfterOutputChange()
    }

    override init() {
        super.init()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, outputDeviceChanged)
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutputAddress, .main, outputDeviceChanged)
    }

    func stopStream() {
        tap?.stop()
        tap = nil
        captureProblem = nil
        if isRecording { isRecording = false }
    }

    func startStream() async {
        await MainActor.run {
            self.captureProblem = nil
            self.heardAudio = false
        }
        do {
            let newTap = try SystemAudioTap()
            audioEngine?.setSampleRate(Float(newTap.sampleRate))
            print("Capturing system audio at \(newTap.sampleRate) Hz")

            var signalSeen = false // Only touched on the tap's queue
            try newTap.start { [weak self] samples in
                guard let self = self else { return }
                // Pass to C++ Engine
                self.audioEngine?.processAudioSamples(samples.baseAddress, count: Int32(samples.count))
                if !signalSeen && samples.contains(where: { $0 != 0 }) {
                    signalSeen = true
                    DispatchQueue.main.async { self.audioDetected() }
                }
            }

            await MainActor.run {
                self.tap = newTap
                self.isRecording = true
                self.watchForSilence()
            }
        } catch {
            await MainActor.run { self.handleCaptureFailure(error) }
        }
    }

    // A denied tap delivers silence rather than an error, and macOS has no public way
    // to ask for the permission's state, so a long silence is the only available signal.
    func watchForSilence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + noAudioHintDelay) { [weak self] in
            guard let self = self, self.isRecording, !self.heardAudio else { return }
            self.captureProblem = .noAudioYet
        }
    }

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
    case noAudioYet
    case failed(String)

    var message: String {
        switch self {
        case .noAudioYet: return "No audio detected. If something is playing, allow this app under System Audio Recording Only."
        case .failed(let reason): return "Capture stopped: \(reason)"
        }
    }
}

struct CoreAudioError: LocalizedError {
    let step: String
    let status: OSStatus

    var errorDescription: String? { "\(step) (Core Audio error \(status))." }
}

private func check(_ status: OSStatus, _ step: String) throws {
    guard status == noErr else { throw CoreAudioError(step: step, status: status) }
}

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
    private(set) var sampleRate: Double = 0
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "VFDVisualizer.SystemAudioTap", qos: .userInteractive)

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

        var pid = ProcessInfo.processInfo.processIdentifier
        let ownProcess: AudioObjectID = try audioProperty(of: system, kAudioHardwarePropertyTranslatePIDToProcessObject, initial: AudioObjectID(kAudioObjectUnknown), qualifierSize: UInt32(MemoryLayout<pid_t>.size), qualifier: &pid, step: "Couldn't identify this app to Core Audio")

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        description.uuid = UUID()
        description.name = "VFD Visualizer"
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID), "Couldn't create the system audio tap")

        let format: AudioStreamBasicDescription = try audioProperty(of: tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription(), step: "Couldn't read the audio format")
        guard isSupportedTapFormat(format) else {
            throw CoreAudioError(step: "The system audio format isn't supported", status: OSStatus(format.mFormatID))
        }
        sampleRate = format.mSampleRate

        let outputDevice: AudioObjectID = try audioProperty(of: system, kAudioHardwarePropertyDefaultOutputDevice, initial: AudioObjectID(kAudioObjectUnknown), step: "Couldn't find the output device")
        let outputUID: Unmanaged<CFString>? = try audioProperty(of: outputDevice, kAudioDevicePropertyDeviceUID, initial: nil, step: "Couldn't identify the output device")
        guard let outputUID = outputUID?.takeRetainedValue() as String? else {
            throw CoreAudioError(step: "Couldn't identify the output device", status: kAudioHardwareUnspecifiedError)
        }

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

    func start(onSamples: @escaping (UnsafeMutableBufferPointer<Float>) -> Void) throws {
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in
            withMonoSamples(in: input, body: onSamples)
        }, "Couldn't connect to the capture device")
        try check(AudioDeviceStart(deviceID, procID), "Couldn't start capturing audio")
    }

    // Safe to call repeatedly, and after a partly failed setup
    func stop() {
        if let procID = procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        if deviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
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

    var frameCount = 0
    for buffer in buffers where buffer.mData != nil && buffer.mNumberChannels > 0 {
        frameCount = max(frameCount, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * Int(buffer.mNumberChannels)))
    }
    guard frameCount > 0 else { return }

    withUnsafeTemporaryAllocation(of: Float.self, capacity: frameCount) { mono in
        mono.initialize(repeating: 0)
        var totalChannels = 0

        for buffer in buffers {
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let channels = Int(buffer.mNumberChannels)
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)

            for frame in 0..<frames {
                for channel in 0..<channels {
                    mono[frame] += samples[frame * channels + channel]
                }
            }
            totalChannels += channels
        }

        for frame in 0..<frameCount {
            mono[frame] /= Float(totalChannels)
        }
        body(mono)
    }
}
