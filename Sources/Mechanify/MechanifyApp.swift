import MechanifyCore
import SwiftUI

@main
struct MechanifyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(nsImage: state.isSounding ? MenuBarIcon.on : MenuBarIcon.off)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar panel: the everyday controls. Everything else lives in Settings.
struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Mechanify", isOn: $state.enabled)
                    .toggleStyle(.switch)
                    .font(.headline)
                Spacer()
                Text(GlobalShortcut.display)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .opacity(state.shortcutEnabled ? 1 : 0)
                    .help("Turns sounds on or off from any app")
            }

            if !state.hasPermission {
                PermissionNotice(state: state)
            } else if let paused = state.muteDescription, state.enabled {
                Label(paused, systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let keyboard = state.newKeyboard {
                NewKeyboardBanner(state: state, keyboard: keyboard)
            }

            LabeledSlider(title: "Volume", value: $state.volume, range: 0...1,
                          low: "speaker.fill", high: "speaker.wave.3.fill") { state.preview() }

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

            LabeledSlider(title: "Tone", value: $state.tone, range: -1...1,
                          lowText: "Deeper", highText: "Brighter") { state.preview() }

            OutputPicker(state: state, compact: true)

            if let message = state.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mechanify™").font(.caption.weight(.semibold))
                    Text("Made with ♥ by Abrar in NYC").font(.caption2).foregroundStyle(.secondary)
                }
                .help("Switch recordings: CC0, from Freesound and OpenGameArt (credits in the README)")
                Spacer()
                Text("\(KeyStats.compact(state.keysToday)) today")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Key presses today (\(state.keysTotal.formatted()) in total). Counts only.")
            }
            HStack {
                Button("Settings…") { state.showSettings() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { state.refreshLatency() }
    }
}

/// Asks once about a keyboard that just typed for the first time.
struct NewKeyboardBanner: View {
    @ObservedObject var state: AppState
    let keyboard: KeyboardInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("New keyboard: \(keyboard.name)", systemImage: "keyboard.badge.ellipsis")
                .font(.callout.weight(.semibold))
            Text("Play sounds when you type on it? Turn this off for a mechanical keyboard that already clicks.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Play Sounds") { state.setSounds(true, for: keyboard.id) }
                    .keyboardShortcut(.defaultAction)
                Button("Keep It Quiet") { state.setSounds(false, for: keyboard.id) }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PermissionNotice: View {
    @ObservedObject var state: AppState

    var body: some View {
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
}

/// Choose where clicks play, with the measured delay and a Bluetooth warning.
struct OutputPicker: View {
    @ObservedObject var state: AppState
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if compact { Text("Play clicks on").font(.caption).foregroundStyle(.secondary) }
            Picker(compact ? "" : "Play clicks on", selection: $state.outputDeviceUID) {
                Text("System default").tag("")
                ForEach(state.outputs) { device in
                    Text(device.isBluetooth ? "\(device.name) (Bluetooth)" : device.name).tag(device.id)
                }
                if state.chosenOutputMissing {
                    Text("Disconnected device").tag(state.outputDeviceUID)
                }
            }
            .labelsHidden(compact)
            if state.chosenOutputMissing {
                Text("That device isn't connected; clicks use the system default until it's back.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ms = state.latencyMs, ms > 0 {
                if ms > 40 {
                    Label {
                        Text(String(format: "Delay ≈ %.0f ms: Bluetooth adds this. Pick the built-in speakers or wired headphones here for instant clicks, even while your music stays on Bluetooth.", ms))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "headphones") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(String(format: "Delay ≈ %.0f ms", ms)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var low: String? = nil
    var high: String? = nil
    var lowText: String? = nil
    var highText: String? = nil
    var onRelease: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                if let low { Image(systemName: low).foregroundStyle(.secondary) }
                if let lowText { Text(lowText).font(.caption2).foregroundStyle(.secondary) }
                Slider(value: $value, in: range) { editing in
                    if !editing { onRelease() }
                }
                if let high { Image(systemName: high).foregroundStyle(.secondary) }
                if let highText { Text(highText).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

private extension View {
    @ViewBuilder func labelsHidden(_ hidden: Bool) -> some View {
        if hidden { labelsHidden() } else { self }
    }
}
