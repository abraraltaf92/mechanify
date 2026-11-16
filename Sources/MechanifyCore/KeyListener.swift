import Foundation
import IOKit.hid

/// A key press or release, reduced to what the sound needs: which edge, and where on
/// the keyboard (as a stereo position). The key itself is not passed on.
public enum KeyEvent: Equatable {
    case down(pan: Float)
    case up(pan: Float)
}

/// Global key listener built on IOKit's HID manager, so every press is known together
/// with the physical keyboard it came from. That lets you silence a keyboard that already
/// makes its own sound (a real mechanical one) while others keep clicking.
///
/// Privacy: keyboards are opened without seizing them, so typing reaches your apps
/// exactly as before. Each report is reduced at once to "down or up" plus the key's
/// left-right position; the key itself is dropped and characters are never produced.
/// Nothing is logged or stored. Keyboard identities (name, vendor, product) are kept only
/// so your per-keyboard choice can be remembered.
///
/// Physical presses only: keys typed by software (automation, remapping tools that post
/// their own events) don't click, and holding a key plays once (HID has no auto-repeat).
///
/// Runs on its own high-priority thread, so a busy main thread can never delay a click.
/// `onKey` is called on that thread; `onNewKeyboard` on the main thread.
///
/// Needs the Input Monitoring permission (System Settings → Privacy & Security).
public final class KeyListener {
    public var onKey: ((KeyEvent) -> Void)?
    /// Called once per run for each keyboard the first time it types.
    public var onKeyboardTyped: ((KeyboardInfo) -> Void)?

    /// Also click for Shift, Control, Option, Command, fn and Caps Lock.
    public var includesModifiers: Bool {
        get { settingsLock.withLock { _includesModifiers } }
        set { settingsLock.withLock { _includesModifiers = newValue } }
    }

    /// Keyboard IDs that click. Any other keyboard is quiet, including one typing for the
    /// first time, so a newly connected mechanical keyboard never doubles its own sound.
    public var audibleKeyboards: Set<String> {
        get { settingsLock.withLock { _audible } }
        set { settingsLock.withLock { _audible = newValue } }
    }

    private var _includesModifiers = true
    private var _audible: Set<String> = [KeyboardInfo.builtInID]
    private let settingsLock = NSLock()

    // Listener-thread state.
    private var manager: IOHIDManager?
    private var runLoop: CFRunLoop?
    private var identities: [UnsafeMutableRawPointer: KeyboardInfo] = [:]
    private var held: [String: Set<UInt32>] = [:]
    private var announced: Set<String> = []

    public init() {}

    deinit { stop() }

    /// Keyboards open right now (for diagnostics). Read from the listener thread's state,
    /// so treat it as approximate.
    public var connectedKeyboards: [KeyboardInfo] {
        Array(Set(identities.values)).sorted { $0.name < $1.name }
    }

    public static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system prompt the first time; afterwards macOS only lists the app
    /// in System Settings, so the menu also offers a direct link there.
    @discardableResult
    public static func requestPermission() -> Bool { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    /// Opens every keyboard (now and as they connect) on a dedicated thread.
    /// Returns false without permission.
    @discardableResult
    public func start() -> Bool {
        if manager != nil { return true }
        guard Self.hasPermission else { return false }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatchingMultiple(manager, [
            [kIOHIDElementUsagePageKey: HIDKeys.keyboardPage],
            [kIOHIDElementUsagePageKey: HIDKeys.appleTopCasePage],
        ] as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<KeyListener>.fromOpaque(context).takeUnretainedValue().deviceConnected(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<KeyListener>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<KeyListener>.fromOpaque(context).takeUnretainedValue().received(value)
        }, context)

        let ready = DispatchSemaphore(value: 0)
        var loop: CFRunLoop?
        var opened = false
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            IOHIDManagerScheduleWithRunLoop(manager, loop!, CFRunLoopMode.defaultMode.rawValue)
            opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
            ready.signal()
            if opened { CFRunLoopRun() }
        }
        thread.name = "Mechanify key listener"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard opened else { return false }
        self.manager = manager
        runLoop = loop
        return true
    }

    public func stop() {
        guard let manager, let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
        self.manager = nil
        self.runLoop = nil
    }

    // MARK: Devices

    private func deviceConnected(_ device: IOHIDDevice) {
        func prop<T>(_ key: String) -> T? { IOHIDDeviceGetProperty(device, key as CFString) as? T }
        identities[Unmanaged.passUnretained(device).toOpaque()] = KeyboardInfo.identify(
            product: prop(kIOHIDProductKey),
            vendorID: prop(kIOHIDVendorIDKey) ?? 0,
            productID: prop(kIOHIDProductIDKey) ?? 0,
            serial: prop(kIOHIDSerialNumberKey),
            builtIn: prop(kIOHIDBuiltInKey) ?? false
        )
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let key = Unmanaged.passUnretained(device).toOpaque()
        if let id = identities.removeValue(forKey: key)?.id { held[id] = nil }
    }

    // MARK: Key reports

    private func received(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let keyboard = identities[Unmanaged.passUnretained(device).toOpaque()] else { return }
        process(page: IOHIDElementGetUsagePage(element), usage: IOHIDElementGetUsage(element),
                pressed: IOHIDValueGetIntegerValue(value) != 0, keyboard: keyboard)
    }

    /// Turns one key report into a `KeyEvent` (internal so tests can feed it reports).
    func process(page: UInt32, usage: UInt32, pressed: Bool, keyboard: KeyboardInfo) {
        guard let code = HIDKeys.keyCode(page: page, usage: usage) else { return }

        // Some keyboards send the same state twice; only real edges count.
        let key = (page << 16) | usage
        var keys = held[keyboard.id, default: []]
        guard pressed ? keys.insert(key).inserted : keys.remove(key) != nil else { return }
        held[keyboard.id] = keys

        if pressed, !announced.contains(keyboard.id) {
            announced.insert(keyboard.id)
            let callback = onKeyboardTyped
            DispatchQueue.main.async { callback?(keyboard) }
        }

        let (modifiers, audible) = settingsLock.withLock { (_includesModifiers, _audible) }
        guard audible.contains(keyboard.id) else { return }
        guard modifiers || !HIDKeys.modifierKeyCodes.contains(code) else { return }
        let pan = KeyLayout.pan(forKeyCode: code)
        onKey?(pressed ? .down(pan: pan) : .up(pan: pan))
    }
}
