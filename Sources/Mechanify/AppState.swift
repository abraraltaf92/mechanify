import AppKit
import MechanifyCore
import ServiceManagement
import SwiftUI

/// Owns the listener and sound engine and keeps them in sync with the settings.
@MainActor
final class AppState: ObservableObject {
    // Sound
    @AppStorage("enabled") var enabled = true { didSet { applyEnabled() } }
    @AppStorage("volume") var volume = 0.6 { didSet { engine.volume = Float(volume) } }
    @AppStorage("profile") var profileID = "Cherry MX Clear" { didSet { loadProfile() } }
    @AppStorage("tone") var tone = 0.0 { didSet { engine.tone = Float(tone) } }
    @AppStorage("releases") var releases = true { didSet { engine.playsReleases = releases } }
    @AppStorage("modifiers") var modifiers = true { didSet { listener.includesModifiers = modifiers } }
    @AppStorage("spatial") var spatial = true { didSet { applySpatial() } }
    @AppStorage("spatialWidth") var spatialWidth = 0.6 { didSet { applySpatial() } }
    /// Output device UID; empty means "follow the system default".
    @AppStorage("outputDevice") var outputDeviceUID = "" { didSet { applyOutput() } }

    // Auto-mute
    @AppStorage("muteDuringCalls") var muteDuringCalls = true { didSet { refreshAutoMute() } }
    @AppStorage("mutedApps") private var mutedAppsStorage = ""

    // Keyboards
    @AppStorage("keyboards") private var keyboardsStorage = Data()
    @Published private(set) var keyboards = KeyboardPreferences()
    /// A keyboard that just typed for the first time; the menu asks whether it should click.
    @Published private(set) var newKeyboard: KeyboardInfo?

    // General
    @AppStorage("shortcutEnabled") var shortcutEnabled = true { didSet { applyShortcut() } }
    @AppStorage("welcomed") private var welcomed = false

    @Published private(set) var hasPermission = KeyListener.hasPermission
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorMessage: String?
    @Published private(set) var latencyMs: Double?
    @Published private(set) var outputs: [OutputDevice] = AudioDevices.outputs()
    @Published private(set) var muteReason: AutoMute.Reason?
    @Published private(set) var keysToday = 0
    @Published private(set) var keysTotal = 0

    let profiles: [SoundProfile]
    private let engine = SoundEngine()
    private let listener = KeyListener()
    private let counter = KeyCounter()
    private let stats = StatsRecorder()
    private var permissionTimer: Timer?
    private var pollTimer: Timer?
    private var deviceObserver: AnyObject?
    private var shortcut: GlobalShortcut?
    private let diagnosing = CommandLine.arguments.contains("--diagnose")

    /// True when clicks are actually playing: switched on, permitted, not auto-muted.
    var isSounding: Bool { enabled && hasPermission && muteReason == nil }

    var mutedApps: [String] {
        mutedAppsStorage.split(separator: "\n").map(String.init)
    }

    init() {
        let profilesDir = Bundle.main.resourceURL?.appendingPathComponent("Profiles")
        profiles = profilesDir.map { SoundProfile.discover(in: $0) } ?? []
        engine.volume = Float(volume)
        engine.tone = Float(tone)
        engine.playsReleases = releases
        engine.outputDeviceUID = outputDeviceUID.isEmpty ? nil : outputDeviceUID
        listener.includesModifiers = modifiers
        keyboards = (try? JSONDecoder().decode(KeyboardPreferences.self, from: keyboardsStorage)) ?? KeyboardPreferences()
        listener.silencedKeyboards = keyboards.silenced
        applySpatial()
        applyEnabled()
        // A saved choice can name a profile that no longer ships (e.g. after an update).
        if let first = profiles.first, !profiles.contains(where: { $0.id == profileID }) {
            profileID = first.id  // didSet loads it
        } else {
            loadProfile()
        }

        // Runs on the listener's own thread and goes straight to the engine,
        // never through the main thread.
        listener.onKey = { [engine, counter, stats] event in
            counter.count(event)
            if case .down = event { stats.recordPress() }
            engine.handle(event)
        }
        listener.onKeyboardTyped = { [weak self] keyboard in
            MainActor.assumeIsolated { self?.keyboardTyped(keyboard) }
        }
        startListening()

        deviceObserver = AudioDevices.observeChanges { [weak self] in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        // Once a second: microphone and frontmost-app checks for auto-mute, and the
        // stats shown in the menu. All cheap status reads.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
        applyShortcut()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [stats] _ in
            stats.save()
        }

        runDiagnosticsIfAsked()
        if !diagnosing && (!welcomed || !hasPermission) {
            DispatchQueue.main.async { self.showWelcome() }
        }
    }

    // MARK: On / off

    func toggleEnabled() { enabled.toggle() }

    private func applyEnabled() {
        engine.isEnabled = enabled && muteReason == nil
        objectWillChange.send()
    }

    // MARK: Auto-mute and stats

    private func tick() {
        refreshAutoMute()
        let snapshot = stats.snapshot()
        if keysToday != snapshot.today(asOf: Date()) { keysToday = snapshot.today(asOf: Date()) }
        if keysTotal != snapshot.total { keysTotal = snapshot.total }
        stats.saveIfNeeded()
    }

    private func refreshAutoMute() {
        let reason = AutoMute.reason(
            microphoneInUse: muteDuringCalls && AudioDevices.isMicrophoneInUse(),
            muteDuringCalls: muteDuringCalls,
            frontmostApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            mutedApps: Set(mutedApps)
        )
        if reason != muteReason {
            muteReason = reason
            applyEnabled()
        }
    }

    /// A readable description of why sounds are paused, if they are.
    var muteDescription: String? {
        switch muteReason {
        case .microphone: "Paused while the microphone is in use"
        case .app(let id): "Paused in \(Self.appName(for: id))"
        case nil: nil
        }
    }

    func addMutedApp(bundleID: String) {
        guard !mutedApps.contains(bundleID) else { return }
        mutedAppsStorage = (mutedApps + [bundleID]).joined(separator: "\n")
        refreshAutoMute()
        objectWillChange.send()
    }

    func removeMutedApp(bundleID: String) {
        mutedAppsStorage = mutedApps.filter { $0 != bundleID }.joined(separator: "\n")
        refreshAutoMute()
        objectWillChange.send()
    }

    /// Asks the user to pick an app; adds it to the "always quiet in" list.
    func chooseMutedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Mute in This App"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        addMutedApp(bundleID: id)
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func resetStats() {
        stats.reset()
        tick()
    }

    // MARK: Keyboards

    private func keyboardTyped(_ keyboard: KeyboardInfo) {
        if keyboards.remember(keyboard) {
            newKeyboard = keyboard   // first time ever: ask in the menu
        }
        saveKeyboards()
    }

    func setSounds(_ on: Bool, for id: String) {
        keyboards.setSounds(on, for: id)
        if newKeyboard?.id == id { newKeyboard = nil }
        saveKeyboards()
    }

    func forgetKeyboard(_ id: String) {
        keyboards.forget(id)
        saveKeyboards()
    }

    func dismissNewKeyboard() { newKeyboard = nil }

    private func saveKeyboards() {
        listener.silencedKeyboards = keyboards.silenced
        keyboardsStorage = (try? JSONEncoder().encode(keyboards)) ?? Data()
    }

    // MARK: Output device

    private func applyOutput() {
        engine.outputDeviceUID = outputDeviceUID.isEmpty ? nil : outputDeviceUID
        refreshLatency()
    }

    private func devicesChanged() {
        outputs = AudioDevices.outputs()
        // The engine follows the system default by itself; a chosen device that just
        // reconnected needs re-applying.
        engine.outputDeviceUID = nil
        engine.outputDeviceUID = outputDeviceUID.isEmpty ? nil : outputDeviceUID
        refreshLatency()
    }

    /// The chosen device is set but not connected right now.
    var chosenOutputMissing: Bool {
        !outputDeviceUID.isEmpty && !outputs.contains { $0.id == outputDeviceUID }
    }

    var currentOutputName: String? { engine.currentOutputName }

    // MARK: Shortcut

    private func applyShortcut() {
        shortcut = shortcutEnabled ? GlobalShortcut { [weak self] in
            MainActor.assumeIsolated { self?.toggleEnabled() }
        } : nil
    }

    // MARK: Windows

    func showWelcome() {
        welcomed = true
        WindowPresenter.show(id: "welcome", title: "Welcome to Mechanify", size: CGSize(width: 460, height: 520)) {
            WelcomeView(state: self)
        }
    }

    func showSettings() {
        WindowPresenter.show(id: "settings", title: "Mechanify Settings", size: CGSize(width: 480, height: 620)) {
            SettingsView(state: self)
        }
    }

    // MARK: Diagnostics

    /// `Mechanify --diagnose <seconds>`: after that long, prints how many key presses and
    /// releases arrived, how many clicks were played and how loud the output got, then
    /// quits. Counts only; which keys were pressed is never recorded.
    private func runDiagnosticsIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--diagnose") else { return }
        let seconds = args.indices.contains(i + 1) ? Double(args[i + 1]) ?? 15 : 15
        print("diagnose: listening for \(Int(seconds)) s, permission \(hasPermission), profile \(profileID), output \(currentOutputName ?? "?"), muted \(muteDescription ?? "no")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            print("diagnose: keyboards open: " + listener.connectedKeyboards.map { "\($0.name)\($0.isBuiltIn ? " (built-in)" : "")" }.joined(separator: ", "))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            let c = counter.snapshot()
            print(String(format: "diagnose: key downs %d, key ups %d, clicks played %d, peak output %.3f, latency %.1f ms",
                         c.downs, c.ups, engine.clicksStarted, engine.peakOutput, engine.outputLatencyMs))
            fflush(stdout)
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: Permission

    private func startListening() {
        if KeyListener.hasPermission, listener.start() {
            hasPermission = true
            permissionTimer?.invalidate()
            permissionTimer = nil
            return
        }
        hasPermission = false
        KeyListener.requestPermission()
        // macOS gives no callback when the user grants access, so check back
        // until it is on; then start the tap without needing a relaunch.
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, KeyListener.hasPermission else { return }
                self.startListening()
            }
        }
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Profile

    private func loadProfile() {
        guard let profile = profiles.first(where: { $0.id == profileID }) ?? profiles.first else {
            errorMessage = "No sound profiles found in the app bundle."
            return
        }
        do {
            try engine.load(profile)
            errorMessage = nil
            latencyMs = engine.outputLatencyMs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func preview() { engine.preview() }

    func refreshLatency() { latencyMs = engine.outputLatencyMs }

    private func applySpatial() {
        engine.spatialWidth = spatial ? Float(spatialWidth) : 0
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = "Launch at login: \(error.localizedDescription)"
        }
        // macOS can hold a new login item until the user approves it in System Settings.
        // Say so and open that page, instead of leaving the switch silently off.
        if on && SMAppService.mainApp.status == .requiresApproval {
            errorMessage = "Approve Mechanify under General → Login Items in System Settings to finish turning this on."
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Thread-safe tally of key events for diagnostics (counts only, never which key).
final class KeyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var downs = 0
    private var ups = 0

    func count(_ event: KeyEvent) {
        lock.withLock {
            if case .down = event { downs += 1 } else { ups += 1 }
        }
    }

    func snapshot() -> (downs: Int, ups: Int) { lock.withLock { (downs, ups) } }
}

/// Keeps `KeyStats` safe across threads and saves it to user defaults now and then
/// (not on every key press).
final class StatsRecorder: @unchecked Sendable {
    private static let key = "keyStats"
    private let lock = NSLock()
    private var stats: KeyStats
    private var dirty = false
    private var lastSave = Date()

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(KeyStats.self, from: $0) }
        stats = saved ?? KeyStats()
    }

    func recordPress() {
        lock.withLock {
            stats.recordPress()
            dirty = true
        }
    }

    func snapshot() -> KeyStats { lock.withLock { stats } }

    func reset() {
        lock.withLock {
            stats.reset()
            dirty = true
        }
        save()
    }

    func saveIfNeeded() {
        guard Date().timeIntervalSince(lastSave) > 30 else { return }
        save()
    }

    func save() {
        let data: Data? = lock.withLock {
            guard dirty else { return nil }
            dirty = false
            return try? JSONEncoder().encode(stats)
        }
        lastSave = Date()
        if let data { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
