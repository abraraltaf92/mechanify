import Foundation

/// A sound profile is a folder named after the switch, holding WAV files:
///
///     Cherry MX Clear/
///       down/  key presses   (required)
///       up/    key releases  (optional)
///
/// WAV files placed directly in the folder also count as presses.
public struct SoundProfile: Identifiable, Hashable {
    public static let preferredOrder = ["Cherry MX Clear", "Cherry MX Red", "Gateron Black", "Cherry MX Blue", "Classic"]

    public let id: String
    public let presses: [URL]
    public let releases: [URL]

    public var displayName: String { id }

    public init(id: String, presses: [URL], releases: [URL] = []) {
        self.id = id
        self.presses = presses
        self.releases = releases
    }

    /// Finds every subfolder of `directory` that holds at least one press sample.
    /// Profiles are returned in `preferredOrder` first, then alphabetically.
    public static func discover(in directory: URL, preferredOrder: [String] = SoundProfile.preferredOrder) -> [SoundProfile] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        let profiles = folders.compactMap { folder -> SoundProfile? in
            guard isDirectory(folder) else { return nil }
            let presses = wavs(in: folder) + wavs(in: folder.appendingPathComponent("down"))
            guard !presses.isEmpty else { return nil }
            return SoundProfile(id: folder.lastPathComponent, presses: presses,
                                releases: wavs(in: folder.appendingPathComponent("up")))
        }
        func rank(_ p: SoundProfile) -> Int { preferredOrder.firstIndex(of: p.id) ?? preferredOrder.count }
        return profiles.sorted { (rank($0), $0.id) < (rank($1), $1.id) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func wavs(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
