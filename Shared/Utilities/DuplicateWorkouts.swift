import Foundation

/// Finds workouts that are the same session recorded twice.
///
/// A real Health store holds duplicates as a matter of course: an Apple Watch
/// records the run, and Strava, Garmin Connect or a gym app writes its own copy
/// of it a few minutes later. Scored as two sessions, the second stacks on the
/// first and one hour of training produces a double-length countdown, which is
/// the single most visible way the app can be wrong about somebody's day.
///
/// Two workouts are one session when their overlap covers at least
/// `overlapThreshold` of the *longer* of the two. Measured against the longer
/// one so a short warm-up logged inside a long match stays its own session, and
/// a copy that was trimmed by a minute at either end still matches.
///
/// The copy that is kept is the better-measured one: more heart-rate coverage,
/// then the longer duration, then the identifier for a stable answer.
public enum DuplicateWorkouts {

    public struct Candidate: Sendable {
        public let id: String
        public let start: Date
        public let end: Date
        public let heartRateCoverage: Double

        public init(id: String, start: Date, end: Date, heartRateCoverage: Double) {
            self.id = id
            self.start = start
            self.end = end
            self.heartRateCoverage = heartRateCoverage
        }

        var duration: TimeInterval { max(end.timeIntervalSince(start), 0) }
    }

    public static let overlapThreshold = 0.5

    /// Identifiers of every workout that duplicates a better-measured one.
    public static func duplicateIDs(in candidates: [Candidate]) -> Set<String> {
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.heartRateCoverage != rhs.heartRateCoverage {
                return lhs.heartRateCoverage > rhs.heartRateCoverage
            }
            if lhs.duration != rhs.duration { return lhs.duration > rhs.duration }
            return lhs.id < rhs.id
        }

        var kept: [Candidate] = []
        var duplicates: Set<String> = []
        for candidate in ranked {
            if kept.contains(where: { isSameSession($0, candidate) }) {
                duplicates.insert(candidate.id)
            } else {
                kept.append(candidate)
            }
        }
        return duplicates
    }

    static func isSameSession(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let overlap = min(lhs.end, rhs.end).timeIntervalSince(max(lhs.start, rhs.start))
        let longer = max(lhs.duration, rhs.duration)
        guard overlap > 0, longer > 0 else { return false }
        return overlap / longer >= overlapThreshold
    }
}
