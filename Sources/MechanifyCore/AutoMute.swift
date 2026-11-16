/// Decides when Mechanify should go quiet on its own.
public enum AutoMute {
    public enum Reason: Equatable {
        /// Some app is using the microphone: a call, a meeting, a recording, dictation.
        case microphone
        /// The frontmost app is on the user's "always quiet in" list (its bundle ID).
        case app(String)
    }

    /// Microphone wins over the app list, so the status reads "in a call" during a call
    /// even if the call app is also on the list.
    public static func reason(
        microphoneInUse: Bool,
        muteDuringCalls: Bool,
        frontmostApp: String?,
        mutedApps: Set<String>
    ) -> Reason? {
        if muteDuringCalls && microphoneInUse { return .microphone }
        if let app = frontmostApp, mutedApps.contains(app) { return .app(app) }
        return nil
    }
}
