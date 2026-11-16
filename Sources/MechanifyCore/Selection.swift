/// Picks a random sample index, never the same one twice in a row, so repeated
/// keystrokes don't sound machine-identical.
public struct SamplePicker<G: RandomNumberGenerator> {
    private var generator: G
    private var last: Int?

    public init(generator: G) {
        self.generator = generator
    }

    public mutating func pick(from count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard count > 1 else { last = 0; return 0 }
        var index = Int.random(in: 0..<count, using: &generator)
        if index == last { index = (index + 1 + Int.random(in: 0..<(count - 1), using: &generator)) % count }
        last = index
        return index
    }
}

extension SamplePicker where G == SystemRandomNumberGenerator {
    public init() { self.init(generator: SystemRandomNumberGenerator()) }
}
