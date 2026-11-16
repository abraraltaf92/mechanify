import MechanifyCore
import SwiftUI

@main
struct MechanifyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(nsImage: state.enabled && state.hasPermission ? MenuBarIcon.on : MenuBarIcon.off)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Mechanify", isOn: $state.enabled)
                .toggleStyle(.switch)
                .font(.headline)

            if !state.hasPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Input Monitoring permission needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Turn on Mechanify under Privacy & Security → Input Monitoring. Sounds start automatically once it's on.\n\nAlready on? It belongs to an older build. Select it, remove it with −, then add this app again (or turn it on when it reappears).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Input Monitoring Settings…") { state.openInputMonitoringSettings() }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Volume").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $state.volume, in: 0...1) { editing in
                        if !editing { state.preview() }
                    }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
            }

            if !state.profiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switch").font(.caption).foregroundStyle(.secondary)
                    Picker("Switch", selection: $state.profileID) {
                        ForEach(state.profiles) { Text($0.displayName).tag($0.id) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .onChange(of: state.profileID) { state.preview() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Key release sounds", isOn: $state.releases)
                Toggle("Spatial audio", isOn: $state.spatial)
                if state.spatial {
                    HStack {
                        Text("Width").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $state.spatialWidth, in: 0.2...1)
                    }
                    .padding(.leading, 20)
                }
            }

            Toggle("Launch at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))

            if let message = state.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let ms = state.latencyMs, ms > 0 {
                if ms > 40 {
                    Label {
                        Text(String(format: "Output delay ≈ %.0f ms. Bluetooth headphones add this delay; built-in speakers or wired headphones give instant clicks.", ms))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "headphones")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(String(format: "Output latency ≈ %.0f ms", ms)).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mechanify™").font(.caption.weight(.semibold))
                    Text("Made with ♥ by Abrar in NYC").font(.caption2).foregroundStyle(.secondary)
                }
                .help("Switch recordings: CC0, from Freesound and OpenGameArt (credits in the README)")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { state.refreshLatency() }
    }
}
