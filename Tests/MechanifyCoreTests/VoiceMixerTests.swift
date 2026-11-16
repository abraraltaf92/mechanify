import Testing
@testable import MechanifyCore

// Sample-exact tests of the real-time mixer, without any audio device.

private func makeClip(_ values: [Float]) -> Clip { values.withUnsafeBufferPointer { Clip($0) } }

private func render(_ mixer: VoiceMixer, frames: Int) -> (left: [Float], right: [Float]) {
    var l = [Float](repeating: 9, count: frames), r = [Float](repeating: 9, count: frames)  // junk: must be overwritten
    l.withUnsafeMutableBufferPointer { lp in
        r.withUnsafeMutableBufferPointer { rp in mixer.render(frames: frames, left: lp.baseAddress!, right: rp.baseAddress!) }
    }
    return (l, r)
}

@Test func silenceWhenNothingIsPlaying() {
    let out = render(VoiceMixer(), frames: 128)
    #expect(out.left.allSatisfy { $0 == 0 } && out.right.allSatisfy { $0 == 0 })
}

@Test func clickStartsOnTheFirstSampleOfTheNextSlice() {
    let mixer = VoiceMixer()
    mixer.trigger(makeClip([1, 0.5, 0.25]), gainLeft: 1, gainRight: 0.5)
    let out = render(mixer, frames: 4)
    #expect(out.left == [1, 0.5, 0.25, 0])
    #expect(out.right == [0.5, 0.25, 0.125, 0])
    #expect(mixer.activeVoices == 0, "finished clips free their voice")
}

@Test func clipsLongerThanASliceContinueSeamlessly() {
    let mixer = VoiceMixer()
    let values = (0..<300).map { Float($0) }
    mixer.trigger(makeClip(values), gainLeft: 1, gainRight: 1)
    var joined: [Float] = []
    for _ in 0..<3 { joined += render(mixer, frames: 128).left }
    #expect(Array(joined.prefix(300)) == values)
    #expect(joined.dropFirst(300).allSatisfy { $0 == 0 })
}

@Test func overlappingClicksAreSummed() {
    let mixer = VoiceMixer()
    mixer.trigger(makeClip([1, 1]), gainLeft: 1, gainRight: 1)
    mixer.trigger(makeClip([0.5]), gainLeft: 1, gainRight: 1)
    #expect(render(mixer, frames: 2).left == [1.5, 1])
}

@Test func whenAllVoicesAreBusyTheOldestIsReplaced() {
    let mixer = VoiceMixer(capacity: 2)
    let long = makeClip([Float](repeating: 1, count: 1000))
    mixer.trigger(long, gainLeft: 1, gainRight: 1)
    _ = render(mixer, frames: 100)                    // voice A is 100 samples in
    mixer.trigger(long, gainLeft: 2, gainRight: 2)
    _ = render(mixer, frames: 10)                     // voice B is 10 in, A is 110 in
    mixer.trigger(makeClip([5]), gainLeft: 1, gainRight: 1)   // replaces A, the oldest
    let out = render(mixer, frames: 1)
    #expect(out.left == [2 + 5], "B (gain 2) keeps playing, A was replaced by the new click")
    #expect(mixer.activeVoices == 1, "the 1-sample click finished; B is still playing")
}

@Test func aFloodOfTriggersIsSafe() {
    let mixer = VoiceMixer(capacity: 4, queueCapacity: 8)
    for _ in 0..<1000 { mixer.trigger(makeClip([0.01, 0.01]), gainLeft: 1, gainRight: 1) }
    let out = render(mixer, frames: 4)
    #expect(out.left[0] > 0 && out.left.allSatisfy { $0.isFinite })
    #expect(mixer.activeVoices == 0)
    mixer.trigger(makeClip([1]), gainLeft: 1, gainRight: 1)
    #expect(render(mixer, frames: 1).left == [1], "still works after the flood")
}

@Test func emptyClipIsHarmless() {
    let mixer = VoiceMixer()
    mixer.trigger(makeClip([]), gainLeft: 1, gainRight: 1)
    #expect(render(mixer, frames: 8).left.allSatisfy { $0 == 0 })
    #expect(mixer.activeVoices == 0)
}

@Test(.timeLimit(.minutes(1)))
func triggersFromManyThreadsWhileRendering() async {
    let mixer = VoiceMixer()
    let clip = makeClip([Float](repeating: 0.001, count: 480))
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<4 {
            group.addTask { for _ in 0..<5_000 { mixer.trigger(clip, gainLeft: 1, gainRight: 1) } }
        }
        group.addTask {
            for _ in 0..<3_000 { _ = render(mixer, frames: 128) }
        }
    }
    for _ in 0..<10 { _ = render(mixer, frames: 128) }
    #expect(mixer.activeVoices == 0, "everything drains")
}
