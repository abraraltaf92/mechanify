import AppKit
import MechanifyCore
import ServiceManagement
import SwiftUI

/// Owns the listener and sound engine and keeps them in sync with the settings.
@MainActor
final class AppState: ObservableObject {
    @AppStorage("enabled") var enabled = true { didSet { engine.isEnabled = enabled; objectWillChange.send() } }
    @AppStorage("volume") var volume = 0.6 { didSet { engine.volume = Float(volume) } }
    @AppStorage("profile") var profileID = "Cherry MX Clear" { didSet { loadProfile() } }
    @AppStorage("releases") var releases = true { didSet { engine.playsReleases = releases } }
    @AppStorage("spatial") var spatial = true { didSet { applySpatial() } }
    @AppStorage("spatialWidth") var spatialWidth = 0.6 { didSet { applySpatial() } }

    @Published private(set) var hasPermission = KeyListener.hasPermission
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorMessage: String?
    @Published private(set) var latencyMs: Double?

    let profiles: [SoundProfile]
    private let engine = SoundEngine()
    private let listener = KeyListener()
    private var permissionTimer: Timer?
    private let counter = KeyCounter()

    init() {
        let profilesDir = Bundle.main.resourceURL?.appendingPathComponent("Profiles")
        profiles = profilesDir.map { SoundProfile.discover(in: $0) } ?? []
        engine.volume = Float(volume)
        engine.isEnabled = enabled
        engine.playsReleases = releases
        applySpatial()
        // A saved choice can name a profile that no longer ships (e.g. after an update).
        if let first = profiles.first, !profiles.contains(where: { $0.id == profileID }) {
            profileID = first.id  // didSet loads it
        } else {
            loadProfile()
        }

        // Runs on the listener's own thread and goes straight to the engine,
        // never through the main thread.
        listener.onKey = { [engine, counter] event in
            counter.count(event)
            engine.handle(event)
        }
        startListening()
        runDiagnosticsIfAsked()
    }

    // MARK: Diagnostics

    /// `Mechanify --diagnose <seconds>`: after that long, prints how many key presses and
    /// releases arrived, how many clicks were played and how loud the output got, then
    /// quits. Counts only; which keys were pressed is never recorded.
    private func runDiagnosticsIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--diagnose") else { return }
        let seconds = args.indices.contains(i + 1) ? Double(args[i + 1]) ?? 15 : 15
        print("diagnose: listening for \(Int(seconds)) s, permission \(hasPermission), profile \(profileID)")
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
