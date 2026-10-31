import MacShotCore
import Testing

struct AutoScrollPolicyTests {
    @Test func scrollsWhileAllIsWell() {
        var policy = AutoScrollPolicy()
        policy.record(.first)
        #expect(policy.decide(elapsed: 0.3, userActivity: false, pointerInside: true) == .scroll)
        policy.record(.appended(80))
        #expect(policy.decide(elapsed: 0.6, userActivity: false, pointerInside: true) == .scroll)
    }

    @Test func anyUserInputStopsForGood() {
        var policy = AutoScrollPolicy()
        policy.record(.first)
        #expect(policy.decide(elapsed: 0.5, userActivity: false, pointerInside: true) == .scroll)
        #expect(policy.decide(elapsed: 1, userActivity: true, pointerInside: true) == .stop(.userTookOver))
        // Stays stopped even when the input ends.
        policy.record(.appended(80))
        #expect(policy.decide(elapsed: 2, userActivity: false, pointerInside: true) == .stop(.userTookOver))
    }

    @Test func pausesOutsideTheFrame() {
        var policy = AutoScrollPolicy()
        policy.record(.first)
        #expect(policy.decide(elapsed: 1, userActivity: false, pointerInside: false) == .pause)
        #expect(policy.decide(elapsed: 2, userActivity: false, pointerInside: true) == .scroll)
    }

    @Test func timeLimit() {
        var policy = AutoScrollPolicy(maximumDuration: 45)
        policy.record(.first)
        #expect(policy.decide(elapsed: 44.9, userActivity: false, pointerInside: true) == .scroll)
        #expect(policy.decide(elapsed: 45, userActivity: false, pointerInside: true) == .stop(.timeLimit))
    }

    @Test func frameLimit() {
        var policy = AutoScrollPolicy(maximumFrames: 3)
        policy.record(.first)
        policy.record(.appended(10))
        #expect(policy.decide(elapsed: 1, userActivity: false, pointerInside: true) == .scroll)
        policy.record(.appended(10))
        #expect(policy.decide(elapsed: 1, userActivity: false, pointerInside: true) == .stop(.frameLimit))
    }

    @Test func repeatedLostFramesStop() {
        var policy = AutoScrollPolicy(maximumLostInARow: 4)
        policy.record(.first)
        for _ in 0..<3 { policy.record(.lost) }
        #expect(policy.decide(elapsed: 1, userActivity: false, pointerInside: true) == .scroll)
        policy.record(.lost)
        #expect(policy.decide(elapsed: 1, userActivity: false, pointerInside: true) == .stop(.lostTrack))
    }

    @Test func endOfContentAfterProgress() {
        var policy = AutoScrollPolicy()
        policy.record(.first)
        policy.record(.unchanged)
        policy.record(.unchanged)
        // Nothing appended yet: the first scroll may just not have landed; keep going (time/frame limits still apply).
        #expect(policy.decide(elapsed: 1, userActivity: false, pointerInside: true) == .scroll)
        policy.record(.appended(60))
        policy.record(.unchanged)
        policy.record(.unchanged)
        #expect(policy.decide(elapsed: 2, userActivity: false, pointerInside: true) == .stop(.endOfContent))
    }

    @Test func lostCounterResetsOnProgress() {
        var policy = AutoScrollPolicy(maximumLostInARow: 2)
        policy.record(.first)
        policy.record(.lost)
        policy.record(.appended(40))
        policy.record(.lost)
        #expect(policy.decide(elapsed: 1, userActivity: false, pointerInside: true) == .scroll)
    }

    @Test func bringingThePointerIntoTheFrameIsNotTakingOver() {
        // Capture was clicked in the toolbar: the pointer starts outside the frame and must be moved in.
        var policy = AutoScrollPolicy()
        policy.record(.first)
        #expect(policy.decide(elapsed: 0.2, userActivity: true, pointerInside: false) == .pause)
        #expect(policy.decide(elapsed: 0.4, userActivity: true, pointerInside: true) == .scroll)
        // Once scrolling, moving the mouse stops it.
        policy.record(.appended(80))
        #expect(policy.decide(elapsed: 0.8, userActivity: true, pointerInside: true) == .stop(.userTookOver))
    }

    @Test func inputBeforeTheFirstScrollIsIgnored() {
        var policy = AutoScrollPolicy()
        policy.record(.first)
        #expect(policy.decide(elapsed: 0.1, userActivity: true, pointerInside: true) == .scroll)
    }
}
