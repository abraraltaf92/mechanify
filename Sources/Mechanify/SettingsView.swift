import MechanifyCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Key release sounds", isOn: $state.releases)
                Text("A softer second sound when a key springs back up, like a real switch.")
                    .settingsNote()
                Toggle("Modifier keys", isOn: $state.modifiers)
                Text("Also click for Shift, Control, Option, Command, Fn and Caps Lock.")
                    .settingsNote()
                Toggle("Spatial audio", isOn: $state.spatial)
                if state.spatial {
                    LabeledSlider(title: "Width", value: $state.spatialWidth, range: 0.2...1,
                                  lowText: "Subtle", highText: "Wide")
                    Text("Each click comes from where the key sits on the keyboard. Easiest to hear on headphones.")
                        .settingsNote()
                }
                LabeledSlider(title: "Tone", value: $state.tone, range: -1...1,
                              lowText: "Deeper", highText: "Brighter") { state.preview() }
            }

            Section("Keyboards") {
                ForEach(keyboardRows, id: \.id) { keyboard in
                    HStack {
                        Image(systemName: keyboard.isBuiltIn ? "laptopcomputer" : "keyboard")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Toggle(keyboard.name, isOn: Binding(
                            get: { !state.keyboards.isSilenced(keyboard.id) },
                            set: { state.setSounds($0, for: keyboard.id) }
                        ))
                        if !keyboard.isBuiltIn {
                            Button {
                                state.forgetKeyboard(keyboard.id)
                            } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless)
                                .help("Forget this keyboard (it will be asked about again next time it types)")
                        }
                    }
                }
                Text("The built-in keyboard clicks; other keyboards start quiet, since they often make their own sound (like a mechanical one). Turn on any that are quiet. New keyboards appear here the first time you type on them, and each choice is remembered.")
                    .settingsNote()
            }

            Section("Output") {
                OutputPicker(state: state)
            }

            Section("Auto-mute") {
                Toggle("Pause while the microphone is in use", isOn: $state.muteDuringCalls)
                Text("Calls, meetings, recordings and dictation. Mechanify only checks whether the microphone is busy; it never listens to it.")
                    .settingsNote()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Always quiet in these apps")
                    if state.mutedApps.isEmpty {
                        Text("None yet").settingsNote()
                    }
                    ForEach(state.mutedApps, id: \.self) { id in
                        HStack {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 18, height: 18)
                            }
                            Text(AppState.appName(for: id))
                            Spacer()
                            Button {
                                state.removeMutedApp(bundleID: id)
                            } label: { Image(systemName: "minus.circle.fill") }
                                .buttonStyle(.borderless)
                                .help("Remove")
                        }
                    }
                    Button("Add App…") { state.chooseMutedApp() }
                }
            }

            Section("Shortcut") {
                Toggle("\(GlobalShortcut.display) turns sounds on or off", isOn: $state.shortcutEnabled)
            }

            Section("Typing stats") {
                LabeledContent("Today", value: state.keysToday.formatted())
                LabeledContent("All time", value: state.keysTotal.formatted())
                Text("Counts of key presses only. Which keys you press is never recorded.")
                    .settingsNote()
                Button("Reset Stats") { state.resetStats() }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Button("Show Welcome Screen…") { state.showWelcome() }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
    }
}

private extension SettingsView {
    /// The built-in keyboard first, then every keyboard that has typed so far.
    var keyboardRows: [KeyboardInfo] {
        let builtIn = KeyboardInfo(id: KeyboardInfo.builtInID, name: "Built-in keyboard", isBuiltIn: true)
        return [builtIn] + state.keyboards.known.filter { !$0.isBuiltIn }
    }
}

private extension Text {
    func settingsNote() -> some View {
        font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
