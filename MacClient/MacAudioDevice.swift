#if os(macOS)
import CoreAudio
import Foundation

/// Read-only HAL output information; no device is opened by these queries.
final class MacAudioDevice {
    private var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                    mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private let queue: DispatchQueue
    private let changed: AudioObjectPropertyListenerBlock

    init(queue: DispatchQueue, changed: @escaping (Bool) -> Void) {
        self.queue = queue
        var previous = Self.output
        self.changed = { _, _ in
            let disconnected = !Self.alive(previous)
            previous = Self.output
            changed(disconnected)
        }
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, self.changed)
        if status != noErr { print("audio: could not watch the output device (\(status)); engine configuration changes still recover output") }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, changed)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) == noErr
        }
    }

    private static var output: AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        _ = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, into: &device)
        return device
    }

    private static func alive(_ device: AudioObjectID) -> Bool {
        var alive: UInt32 = 0
        return read(device, kAudioDevicePropertyDeviceIsAlive, into: &alive) && alive != 0
    }

    static var bufferDuration: Double {
        var frames: UInt32 = 0
        var rate: Float64 = 0
        let device = output
        guard read(device, kAudioDevicePropertyBufferFrameSize, into: &frames),
              read(device, kAudioDevicePropertyNominalSampleRate, into: &rate) else { return 0 }
        return duration(frames: frames, rate: rate)
    }

    static func duration(frames: UInt32, rate: Double) -> Double {
        rate.isFinite && rate > 0 ? Double(frames) / rate : 0
    }

    static var name: String {
        var name: CFString = "no output" as CFString
        _ = read(output, kAudioObjectPropertyName, into: &name)
        return name as String
    }
}
#endif
