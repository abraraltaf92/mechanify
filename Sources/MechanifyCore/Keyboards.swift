import Foundation

/// A physical keyboard, as far as Mechanify needs to know it.
public struct KeyboardInfo: Codable, Hashable, Identifiable {
    /// Stable across reconnects: "built-in", or vendor:product:serial.
    public let id: String
    public let name: String
    public let isBuiltIn: Bool

    public init(id: String, name: String, isBuiltIn: Bool) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
    }

    public static let builtInID = "built-in"

    /// Builds the identity from what the keyboard reports about itself. A Mac's own
    /// keyboard shows up as several HID devices (keyboard, trackpad, top case); they all
    /// say Built-In, so they collapse into one entry.
    public static func identify(product: String?, vendorID: Int, productID: Int, serial: String?, builtIn: Bool) -> KeyboardInfo {
        if builtIn {
            return KeyboardInfo(id: builtInID, name: "Built-in keyboard", isBuiltIn: true)
        }
        let name = product?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Keyboard"
        let tail = serial?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? name
        return KeyboardInfo(id: "\(vendorID):\(productID):\(tail)", name: name, isBuiltIn: false)
    }
}

/// Which keyboards play sounds.
///
/// The built-in keyboard plays unless you switch it off. Any other keyboard stays quiet
/// until you switch it on: an external keyboard is often a mechanical one that already
/// makes its own sound, and doubling it is worse than a moment of silence on a quiet one.
public struct KeyboardPreferences: Codable, Equatable {
    public private(set) var known: [KeyboardInfo] = []
    /// Explicit choices: keyboard ID → sounds on. Missing means the default above.
    public private(set) var choices: [String: Bool] = [:]

    public init() {}

    public func isSilenced(_ id: String) -> Bool { !(choices[id] ?? (id == KeyboardInfo.builtInID)) }
    public func isKnown(_ id: String) -> Bool { id == KeyboardInfo.builtInID || known.contains { $0.id == id } }
    public func hasChoice(_ id: String) -> Bool { choices[id] != nil }

    /// Keyboards that click: the set the key listener lets through. Everything else, including
    /// a keyboard typing for the very first time, is quiet.
    public var audible: Set<String> {
        let ids = Set(known.map(\.id) + choices.keys + [KeyboardInfo.builtInID])
        return ids.filter { !isSilenced($0) }
    }

    // Saved form: `known` and `choices`. Settings saved by 1.3 builds before this change
    // used `silenced` (a deny list); read it so those choices carry over.
    private enum CodingKeys: String, CodingKey { case known, choices, silenced }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        known = try c.decodeIfPresent([KeyboardInfo].self, forKey: .known) ?? []
        choices = try c.decodeIfPresent([String: Bool].self, forKey: .choices) ?? [:]
        for id in try c.decodeIfPresent([String].self, forKey: .silenced) ?? [] where choices[id] == nil {
            choices[id] = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(known, forKey: .known)
        try c.encode(choices, forKey: .choices)
    }

    /// Records a keyboard the first time it types. Returns true if it was new.
    @discardableResult
    public mutating func remember(_ keyboard: KeyboardInfo) -> Bool {
        if let i = known.firstIndex(where: { $0.id == keyboard.id }) {
            known[i] = keyboard  // keep the latest name
            return false
        }
        known.append(keyboard)
        return !keyboard.isBuiltIn
    }

    public mutating func setSounds(_ on: Bool, for id: String) {
        choices[id] = on
    }

    public mutating func forget(_ id: String) {
        known.removeAll { $0.id == id }
        choices[id] = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
