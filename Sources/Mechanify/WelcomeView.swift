import MechanifyCore
import SwiftUI

/// First-launch walkthrough. The permission row turns green on its own once access is
/// granted, so it doubles as the "is it working?" screen.
struct WelcomeView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("Welcome to Mechanify").font(.title.bold())
                Text("Mechanical keyboard sounds for every key you press, in any app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                Step(number: 1, done: state.hasPermission,
                     title: state.hasPermission ? "Keyboard access is on" : "Allow keyboard access",
                     detail: "macOS calls this Input Monitoring. Mechanify only notices that a key went down or up and where it sits on the keyboard, never what you type. Nothing is stored or sent anywhere.") {
                    if !state.hasPermission {
                        Button("Open Input Monitoring Settings…") { state.openInputMonitoringSettings() }
                    }
                }
                Step(number: 2, done: false, title: "Pick a switch",
                     detail: "Click the keycap icon in the menu bar. Try Cherry MX Clear for a satisfying thock, Red for quiet, Blue for loud clicks.") { EmptyView() }
                Step(number: 3, done: false, title: "Make it yours",
                     detail: "Settings has key-release sounds, spatial audio, auto-mute during calls, and \(GlobalShortcut.display) to turn sounds on or off anywhere.") { EmptyView() }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            Button(state.hasPermission ? "Start Typing" : "Done") { WindowPresenter.close(id: "welcome") }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(28)
        .frame(width: 460)
    }
}

private struct Step<Extra: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.bold()).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
    }
}
