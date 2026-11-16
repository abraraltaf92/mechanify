import Foundation

/// A sound profile is a folder of WAV files; the folder name is its id.
public struct SoundProfile: Identifiable, Hashable {
    public let id: String
    public let samples: [URL]

    public var displayName: String { id.prefix(1).uppercased() + id.dropFirst() }

    /// Finds every subfolder of `directory` that holds at least one .wav file.
    /// Profiles are returned in `preferredOrder` first, then alphabetically.
    public static func discover(in directory: URL, preferredOrder: [String] = ["natural", "deep", "crisp"]) -> [SoundProfile] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        let profiles = folders.compactMap { folder -> SoundProfile? in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
            let wavs = files.filter { $0.pathExtension.lowercased() == "wav" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            return wavs.isEmpty ? nil : SoundProfile(id: folder.lastPathComponent, samples: wavs)
        }
        func rank(_ p: SoundProfile) -> Int { preferredOrder.firstIndex(of: p.id) ?? preferredOrder.count }
        return profiles.sorted { (rank($0), $0.id) < (rank($1), $1.id) }
    }
}
