import Foundation

/// Safety rules for automatic scrolling. Pure: the session feeds it what happened, it decides what to do next.
/// Automatic scrolling must never trap the user: it stops for good on any user input, a time / frame limit,
/// repeated unmatched frames or the end of the content, and pauses while the pointer is outside the frame.
public struct AutoScrollPolicy: Sendable {
    public enum StopReason: Equatable, Sendable {
        case userTookOver
        case timeLimit
        case frameLimit
        case lostTrack
        case endOfContent
    }

    public enum Decision: Equatable, Sendable {
        case scroll
        /// Don't scroll this round (pointer outside the frame), keep watching.
        case pause
        /// Automatic scrolling is over; the session continues as manual scrolling (or finishes on end of content).
        case stop(StopReason)
    }

    public let maximumDuration: TimeInterval
    public let maximumFrames: Int
    public let maximumLostInARow: Int
    public let unchangedForEnd: Int

    public private(set) var frames = 0
    public private(set) var lostInARow = 0
    public private(set) var unchangedInARow = 0
    public private(set) var appended = 0
    public private(set) var stopped: StopReason?
    /// True while scrolling is underway. Before the first scroll and while paused the user must be free to move
    /// the pointer into the frame, so input only counts as taking over when armed.
    public private(set) var armed = false

    public init(maximumDuration: TimeInterval = 45, maximumFrames: Int = 120, maximumLostInARow: Int = 4, unchangedForEnd: Int = 2) {
        self.maximumDuration = maximumDuration
        self.maximumFrames = maximumFrames
        self.maximumLostInARow = maximumLostInARow
        self.unchangedForEnd = unchangedForEnd
    }

    /// Records the result of the frame captured after the previous scroll.
    public mutating func record(_ result: ScrollingCapture.AddResult) {
        frames += 1
        switch result {
        case .first:
            break
        case .appended:
            appended += 1
            lostInARow = 0
            unchangedInARow = 0
        case .unchanged:
            unchangedInARow += 1
        case .lost:
            lostInARow += 1
        case .full:
            stopped = stopped ?? .endOfContent
        }
    }

    /// - Parameters:
    ///   - elapsed: seconds since automatic scrolling started.
    ///   - userActivity: the user moved the pointer, scrolled, clicked or typed since the last decision
    ///     (ignored until scrolling is underway, so the pointer can be brought into the frame).
    ///   - pointerInside: the pointer is over the captured frame (scroll events go to what is under it).
    public mutating func decide(elapsed: TimeInterval, userActivity: Bool, pointerInside: Bool) -> Decision {
        if let stopped { return .stop(stopped) }
        let reason: StopReason? =
            if userActivity, armed { .userTookOver }
            else if elapsed >= maximumDuration { .timeLimit }
            else if frames >= maximumFrames { .frameLimit }
            else if lostInARow >= maximumLostInARow { .lostTrack }
            else if appended > 0, unchangedInARow >= unchangedForEnd { .endOfContent }
            else { nil }
        if let reason {
            stopped = reason
            armed = false
            return .stop(reason)
        }
        armed = pointerInside
        return pointerInside ? .scroll : .pause
    }
}
