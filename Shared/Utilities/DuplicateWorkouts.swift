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

        // Kept workouts sorted by start. A kept workout can only overlap the
        // candidate if it starts before the candidate ends and no earlier than
        // the candidate's start minus the longest kept duration, so each
        // candidate checks only that window instead of every kept workout.
        var kept: [Candidate] = []
        var longestKept: TimeInterval = 0
        var duplicates: Set<String> = []
        for candidate in ranked {
            var index = firstIndex(in: kept, startingAtOrAfter: candidate.start.addingTimeInterval(-longestKept))
            var isDuplicate = false
            while index < kept.count, kept[index].start < candidate.end {
                if isSameSession(kept[index], candidate) {
                    isDuplicate = true
                    break
                }
                index += 1
            }
            if isDuplicate {
                duplicates.insert(candidate.id)
            } else {
                kept.insert(candidate, at: firstIndex(in: kept, startingAtOrAfter: candidate.start))
                longestKept = max(longestKept, candidate.duration)
            }
        }
        return duplicates
    }

    /// The first index whose start is at or after `date` in a start-sorted array.
    private static func firstIndex(in sorted: [Candidate], startingAtOrAfter date: Date) -> Int {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].start < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    static func isSameSession(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let overlap = min(lhs.end, rhs.end).timeIntervalSince(max(lhs.start, rhs.start))
        let longer = max(lhs.duration, rhs.duration)
        guard overlap > 0, longer > 0 else { return false }
        return overlap / longer >= overlapThreshold
    }
}
