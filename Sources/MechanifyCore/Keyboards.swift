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

/// Which keyboards play sounds. Unknown keyboards play until the user decides, and the
/// built-in keyboard plays unless switched off.
public struct KeyboardPreferences: Codable, Equatable {
    public private(set) var known: [KeyboardInfo] = []
    public private(set) var silenced: Set<String> = []

    public init() {}

    public func isSilenced(_ id: String) -> Bool { silenced.contains(id) }
    public func isKnown(_ id: String) -> Bool { id == KeyboardInfo.builtInID || known.contains { $0.id == id } }

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
        if on { silenced.remove(id) } else { silenced.insert(id) }
    }

    public mutating func forget(_ id: String) {
        known.removeAll { $0.id == id }
        silenced.remove(id)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
