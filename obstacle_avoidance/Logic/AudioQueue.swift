/*
 An object class to store the audio queue information sent from the DecisionBlock to the UI.
 Includes announcement pacing: cooldown, duplicate suppression by (name, corridor), and
 popNextAnnouncement which can fall through to the next-highest threat obstacle.

 Current Author: Darien Aranda
 Previous Author: Scott Schnieders
 Last modfiied: 2/28/2025
 */
import Foundation
import HeapModule

struct AudioQueueVertex: Comparable {
    let threatLevel: Float16  // Threat level of the obstacle between 0-100, with 100 being the greatest threat.
    let objName: String // Name of the obstacle
    let corridorPosition: String // Angle of the obstacle in left/right/center.
    let vert: String // Vertical postionality of an object
    /// Distance from the user to the obstacle in meters (see `formattedDist` for display).
    let distance: Float16

    // Min-heap stores smallest "Comparable" first; higher threat must sort before lower, so invert comparison.
    static func < (lhs: AudioQueueVertex, rhs: AudioQueueVertex) -> Bool {
        lhs.threatLevel > rhs.threatLevel
    }
}

extension AudioQueueVertex {
    func roundingDistance(distance: Double) -> Double {
        let decimalVal = distance - floor(distance)
        if decimalVal > 0.7 {
            return ceil(distance)
        }
        return floor(distance)
    }

    var formattedDist: String {
        let unitPref = UserDefaults.standard.string(forKey: "measurementType") ?? "feet"
        if unitPref == "meters" {
            var meters = Double(self.distance)
            if meters > 1 {
                meters = roundingDistance(distance: meters)
            }
            return String(format: "%.0f meters", meters)
        } else {
            var feet = Double(self.distance) * 3.28084
            if feet > 1 {
                feet = roundingDistance(distance: feet)
            }
            return String(format: "%.0f feet", feet)
        }
    }

    var announcementMessage: String {
        "\(objName) \(corridorPosition) \(formattedDist)"
    }
}

// MARK: - Announcement policy (centralized)

private struct AnnouncedEntry {
    let objectName: String
    let corridorPosition: String
    let distance: Float16
}

enum AudioAnnouncementPolicy {
    /// Minimum seconds between successful announcements (VoiceOver pacing).
    static let announceInterval: TimeInterval = 3
    /// Relative similarity: if fractional change is below this vs. a recent same (name, corridor), treat as duplicate.
    static let relativeDistanceTolerance: Float16 = 0.15
    /// Minimum absolute distance change (meters) to count as "dramatic" at close range (~0–12 ft depth).
    static let absoluteDistanceFloorMeters: Float16 = 0.5
    static let maxRecentAnnouncements = 5
}

final class AudioQueue {
    static var queue = Heap<AudioQueueVertex>()

    private static var lastAnnounceTime: Date = .distantPast
    private static var lastAnnouncedList: [AnnouncedEntry] = []

    static func addToHeap(_ processedObject: ProcessedObject) {
        let newVertex = AudioQueueVertex(
            threatLevel: processedObject.threatLevel,
            objName: processedObject.objName,
            corridorPosition: processedObject.corridorPosition,
            vert: processedObject.vert,
            distance: processedObject.distance
        )
        queue.insert(newVertex)
    }

    static func clearQueue() {
        queue = Heap<AudioQueueVertex>()
    }

    /// Clears pacing history (e.g. debugging). Does not clear the heap.
    static func resetAnnouncementHistory() {
        lastAnnounceTime = .distantPast
        lastAnnouncedList = []
    }

    /// Pops the highest-threat obstacle that passes `threshold` and announcement policy, or `nil`.
    /// - Cooldown: returns `nil` without popping so the heap is preserved until the interval elapses.
    /// - Below threshold on the current max: clears the heap (no remaining vertex can qualify).
    /// - Duplicate (same name + corridor, similar distance): discards that vertex and tries the next in the heap.
    static func popNextAnnouncement(threshold: Float16) -> AudioQueueVertex? {
        let now = Date()
        if now.timeIntervalSince(lastAnnounceTime) < AudioAnnouncementPolicy.announceInterval {
            return nil
        }

        while let candidate = queue.popMin() {
            if candidate.threatLevel < threshold {
                clearQueue()
                return nil
            }
            if isDuplicateSuppressed(candidate) {
                continue
            }
            recordSuccessfulAnnouncement(candidate)
            return candidate
        }
        return nil
    }

    /// Single pop for ordering / tests; does not apply cooldown or duplicate suppression and does not update history.
    static func popHighestPriorityObject(threshold: Float16) -> AudioQueueVertex? {
        guard let candidate = queue.popMin() else {
            return nil
        }
        if candidate.threatLevel >= threshold {
            return candidate
        }
        return nil
    }

    private static func isDuplicateSuppressed(_ v: AudioQueueVertex) -> Bool {
        let epsilon: Float16 = 1e-6
        for entry in lastAnnouncedList {
            guard v.objName == entry.objectName, v.corridorPosition == entry.corridorPosition else { continue }
            let ref = max(entry.distance, epsilon)
            let delta = abs(v.distance - entry.distance)
            let relativeThreshold = AudioAnnouncementPolicy.relativeDistanceTolerance * ref
            let minChange = max(relativeThreshold, AudioAnnouncementPolicy.absoluteDistanceFloorMeters)
            if delta <= minChange {
                return true
            }
        }
        return false
    }

    private static func recordSuccessfulAnnouncement(_ v: AudioQueueVertex) {
        lastAnnounceTime = Date()
        lastAnnouncedList.append(AnnouncedEntry(
            objectName: v.objName,
            corridorPosition: v.corridorPosition,
            distance: v.distance
        ))
        if lastAnnouncedList.count > AudioAnnouncementPolicy.maxRecentAnnouncements {
            lastAnnouncedList.removeFirst()
        }
    }
}
