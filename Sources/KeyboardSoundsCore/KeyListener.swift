import CoreGraphics
import Foundation

/// Global key-down listener built on a listen-only CGEventTap.
///
/// Privacy: the tap is listen-only (it cannot change or block input) and the
/// callback never reads which key was pressed. It only checks the auto-repeat
/// flag, then reports "a key went down". Nothing is logged or stored.
///
/// Needs the Input Monitoring permission (System Settings → Privacy & Security).
public final class KeyListener {
    public var onKeyDown: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init() {}

    deinit { stop() }

    public static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt the first time; afterwards macOS only lists the app
    /// in System Settings, so the menu also offers a direct link there.
    @discardableResult
    public static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    public var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Installs the tap on the main run loop. Returns false without permission.
    @discardableResult
    public func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyListenerCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables taps whose callback stalls; switch it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            // Holding a key fires repeats; one click per physical press sounds right.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            onKeyDown?()
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
