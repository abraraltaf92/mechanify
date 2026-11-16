import CoreAudio
import Foundation

/// An audio output the user can send clicks to.
public struct OutputDevice: Identifiable, Hashable {
    /// Core Audio's persistent UID, stable across reboots and reconnects.
    public let id: String
    public let name: String
    public let isBluetooth: Bool
    let deviceID: AudioDeviceID
}

/// Read-only queries of the Mac's audio hardware. Nothing here opens or records audio:
/// "is the microphone in use" reads a status flag Core Audio keeps for every device.
public enum AudioDevices {
    /// Every device that can play sound, in Core Audio's order.
    public static func outputs() -> [OutputDevice] {
        allDeviceIDs().compactMap { id in
            guard streamCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let transport: UInt32 = value(id, kAudioDevicePropertyTransportType) ?? 0
            return OutputDevice(
                id: uid,
                name: string(id, kAudioObjectPropertyName) ?? uid,
                isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                deviceID: id
            )
        }
    }

    /// The device macOS plays sound through right now.
    public static func defaultOutput() -> OutputDevice? {
        guard let id: AudioDeviceID = value(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        return outputs().first { $0.deviceID == id }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        outputs().first { $0.id == uid }?.deviceID
    }

    /// True while any app is using any microphone (a call, a recording, dictation).
    public static func isMicrophoneInUse() -> Bool {
        allDeviceIDs().contains { id in
            streamCount(id, scope: kAudioObjectPropertyScopeInput) > 0
                && (value(id, kAudioDevicePropertyDeviceIsRunningSomewhere) as UInt32? ?? 0) != 0
        }
    }

    /// Calls `onChange` on the main queue when devices are added or removed (AirPods
    /// connecting, headphones plugged in) or the default output changes. Keep the
    /// returned token alive for as long as you want updates.
    public static func observeChanges(_ onChange: @escaping () -> Void) -> AnyObject {
        DeviceObserver(onChange)
    }

    // MARK: Core Audio helpers

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func streamCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func value<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var result: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &result) == noErr,
              let cf = result?.takeRetainedValue() else { return nil }
        return cf as String
    }
}

private final class DeviceObserver {
    private let block: AudioObjectPropertyListenerBlock
    private let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice]

    init(_ onChange: @escaping () -> Void) {
        block = { _, _ in onChange() }
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }

    deinit {
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }
}
