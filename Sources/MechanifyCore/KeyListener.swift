import CoreGraphics
import Foundation

/// A key press or release, reduced to what the sound needs: which edge, and where on
/// the keyboard (as a stereo position). The key itself is not passed on.
public enum KeyEvent: Equatable {
    case down(pan: Float)
    case up(pan: Float)
}

/// Global key listener built on a listen-only CGEventTap.
///
/// Privacy: the tap is listen-only (it cannot change or block input). The callback reads
/// the key code only to look up the key's left-right position, then drops it; characters
/// are never requested. Nothing is logged or stored.
///
/// The tap runs on its own high-priority thread, so a busy main thread (menus, SwiftUI)
/// can never delay a click. `onKey` is called on that thread.
///
/// Needs the Input Monitoring permission (System Settings → Privacy & Security).
public final class KeyListener {
    public var onKey: ((KeyEvent) -> Void)?

    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    public init() {}

    deinit { stop() }

    public static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards macOS only lists the app
    /// in System Settings, so the menu also offers a direct link there.
    @discardableResult
    public static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    /// Installs the tap on a dedicated thread. Returns false without permission.
    @discardableResult
    public func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyListenerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        var loop: CFRunLoop?
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Mechanify key listener"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        runLoop = loop
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil
        runLoop = nil
    }

    /// Turns one tapped event into a `KeyEvent` (internal so tests can feed it events).
    func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps whose callback stalls; switch it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            // Holding a key fires repeats; one click per physical press sounds right.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            onKey?(.down(pan: KeyLayout.pan(forKeyCode: event.getIntegerValueField(.keyboardEventKeycode))))
        case .keyUp:
            onKey?(.up(pan: KeyLayout.pan(forKeyCode: event.getIntegerValueField(.keyboardEventKeycode))))
        default:
            break
        }
    }
}

private func keyListenerCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<KeyListener>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
    }
    return Unmanaged.passUnretained(event)
}
