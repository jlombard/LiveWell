import Foundation
import SwiftData

// The app's own store. Health data is copied in by UUID so nothing is counted twice,
// and every value carries where it came from.

@Model
final class WorkoutEntry {
    /// The HealthKit UUID. Unique, so a re-delivered workout updates instead of duplicating.
    @Attribute(.unique) var uuid: UUID
    /// HealthKit activity name, e.g. "functionalStrengthTraining". Mapped to a CSV type at export
    /// time, so changing the mapping in Settings re-maps history too.
    var activity: String
    var start: Date
    var end: Date
    var minutes: Double
    var sourceName: String
    /// Provenance raw value: "measured" (Watch or another app) or "manual" (logged by tap here).
    var provenance: String

    init(uuid: UUID, activity: String, start: Date, end: Date, minutes: Double, sourceName: String, provenance: String) {
        self.uuid = uuid; self.activity = activity; self.start = start; self.end = end
        self.minutes = minutes; self.sourceName = sourceName; self.provenance = provenance
    }
}

@Model
final class HealthReading {
    @Attribute(.unique) var uuid: UUID
    /// "vo2max" or "weight"
    var kind: String
    var date: Date
    var value: Double
    /// "estimated" for Apple's VO2 max; "measured" or "manual" for weight.
    var provenance: String

    init(uuid: UUID, kind: String, date: Date, value: Double, provenance: String) {
        self.uuid = uuid; self.kind = kind; self.date = date; self.value = value; self.provenance = provenance
    }
}

@Model
final class MeasurementEntry {
    /// Measurement key (the checkins.csv column).
    var key: String
    /// yyyy-MM-dd
    var day: String
    var value: Double
    var provenance: String
    /// The protocol line shown when it was taken, so later readings can be compared fairly.
    var protocolLine: String
    var savedAt: Date

    init(key: String, day: String, value: Double, provenance: String, protocolLine: String, savedAt: Date) {
        self.key = key; self.day = day; self.value = value; self.provenance = provenance
        self.protocolLine = protocolLine; self.savedAt = savedAt
    }
}

@Model
final class Reflection {
    var prompt: String
    var text: String
    var date: Date
    init(prompt: String, text: String, date: Date) { self.prompt = prompt; self.text = text; self.date = date }
}

@Model
final class WeekCommitment {
    /// yyyy-MM-dd of the Monday.
    var weekStart: String
    var habitKeys: [String]
    var date: Date
    init(weekStart: String, habitKeys: [String], date: Date) {
        self.weekStart = weekStart; self.habitKeys = habitKeys; self.date = date
    }
}

/// One committed week with its per-habit targets (see LiveWellCore's WeekRecord). Kept in the
/// order saved; also written to app/commitments.json for the Mac.
@Model
final class CommitmentRecord {
    var weekStart: String
    var weekEnd: String
    /// The WeekRecord as JSON.
    var record: Data
    var savedAt: Date
    init(weekStart: String, weekEnd: String, record: Data, savedAt: Date) {
        self.weekStart = weekStart; self.weekEnd = weekEnd; self.record = record; self.savedAt = savedAt
    }
}
