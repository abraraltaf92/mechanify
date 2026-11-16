import os

/// A clip in memory: 48 kHz mono float samples. Clips are allocated once per profile and
/// never freed while the app runs, so a playing voice can never point at freed memory.
struct Clip {
    let samples: UnsafePointer<Float>
    let count: Int

    init(_ values: UnsafeBufferPointer<Float>) {
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: max(1, values.count))
        if let base = values.baseAddress { storage.initialize(from: base, count: values.count) }
        samples = UnsafePointer(storage)
        count = values.count
    }
}

/// The real-time part of the sound engine: mixes up to `capacity` overlapping clicks.
///
/// `trigger` is called from the key listener's thread; `render` from Core Audio's render
/// thread once per output slice. A triggered click starts at the first sample of the next
/// slice, so it is never more than one slice (~2.7 ms) late. The render path never
/// allocates and never waits: if the trigger queue is busy for that instant, new clicks
/// are picked up on the next slice instead.
final class VoiceMixer {
    struct Voice {
        var clip: Clip
        var position = 0
        var gainLeft: Float
        var gainRight: Float
    }

    let capacity: Int
    private var voices: ContiguousArray<Voice?>        // render thread only
    private var pending: ContiguousArray<Voice?>       // guarded by `lock`
    private var pendingCount = 0                       // guarded by `lock`
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    init(capacity: Int = 32, queueCapacity: Int = 64) {
        self.capacity = capacity
        voices = ContiguousArray(repeating: nil, count: capacity)
        pending = ContiguousArray(repeating: nil, count: queueCapacity)
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Queues a click to start on the next render slice. If more clicks arrive between two
    /// slices than the queue holds (64), the extras are dropped: they would be inaudible
    /// in that pile-up anyway.
    func trigger(_ clip: Clip, gainLeft: Float, gainRight: Float) {
        os_unfair_lock_lock(lock)
        if pendingCount < pending.count {
            pending[pendingCount] = Voice(clip: clip, gainLeft: gainLeft, gainRight: gainRight)
            pendingCount += 1
        }
        os_unfair_lock_unlock(lock)
    }

    /// Diagnostics, written on the render thread: clicks started and loudest output sample.
    private(set) var clicksStarted = 0
    private(set) var peakOutput: Float = 0

    /// Number of clicks currently sounding (render-thread view; for tests and diagnostics).
    var activeVoices: Int { voices.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }

    /// Writes `frames` samples of mixed output into `left` and `right`.
    func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        left.update(repeating: 0, count: frames)
        right.update(repeating: 0, count: frames)

        if os_unfair_lock_trylock(lock) {
            for i in 0..<pendingCount {
                if let voice = pending[i] { start(voice) }
                pending[i] = nil
            }
            pendingCount = 0
            os_unfair_lock_unlock(lock)
        }

        for i in 0..<voices.count {
            guard var voice = voices[i] else { continue }
            let n = min(frames, voice.clip.count - voice.position)
            let src = voice.clip.samples + voice.position
            for j in 0..<n {
                left[j] += src[j] * voice.gainLeft
                right[j] += src[j] * voice.gainRight
            }
            voice.position += n
            voices[i] = voice.position >= voice.clip.count ? nil : voice
        }
        for j in 0..<frames { peakOutput = max(peakOutput, abs(left[j]), abs(right[j])) }
    }

    /// Puts a click in a free slot, or replaces the click that has played longest.
    private func start(_ voice: Voice) {
        var slot = 0
        var oldest = -1
        for i in 0..<voices.count {
            guard let v = voices[i] else { slot = i; oldest = Int.max; break }
            if v.position > oldest { oldest = v.position; slot = i }
        }
        voices[slot] = voice
        clicksStarted += 1
    }
}
