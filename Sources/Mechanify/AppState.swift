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
        listener.onKey = { [engine] event in engine.handle(event) }
        startListening()
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
