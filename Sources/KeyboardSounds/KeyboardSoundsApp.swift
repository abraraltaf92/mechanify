import KeyboardSoundsCore
import SwiftUI

@main
struct KeyboardSoundsApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.enabled && state.hasPermission ? "keyboard.fill" : "keyboard")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Keyboard sounds", isOn: $state.enabled)
                .toggleStyle(.switch)
                .font(.headline)

            if !state.hasPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Input Monitoring permission needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Turn on Keyboard Sounds under Privacy & Security → Input Monitoring. Sounds start automatically once it's on.")
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
                    Text("Sound").font(.caption).foregroundStyle(.secondary)
                    Picker("Sound", selection: $state.profileID) {
                        ForEach(state.profiles) { Text($0.displayName).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: state.profileID) { state.preview() }
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

            Divider()
            HStack {
                Text("Sounds: CC0, unicaegames").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
