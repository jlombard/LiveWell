import Foundation

/// Where a value came from. Shown beside every number so nothing is ever a guess.
public enum Provenance: String, Codable, Sendable {
    case measured   // recorded by a device (a Watch workout)
    case estimated  // a device estimate (Apple's VO2 max)
    case manual     // typed or tapped in by the person
    case missing    // "not measured"
}

/// What a habit counts.
public enum HabitSource: Codable, Equatable, Sendable {
    /// Sessions of any of these workout types (the names used in workouts.csv).
    case workouts(types: [String])
    /// Sum of Apple Exercise minutes.
    case exerciseMinutes
    /// On-plan food days. Owned by the Mac until Phase 2; read from data.json.
    case planDays
}

public struct HabitDefinition: Codable, Equatable, Identifiable, Sendable {
    public var key: String
    public var name: String
    public var goal: Double
    public var source: HabitSource
    /// Sessions shorter than this don't count. 0 counts everything.
    public var minMinutes: Double
    /// Pillar keys this habit feeds; the first one is the bar that glows after logging.
    public var pillars: [String]
    /// "Rows build your cardio." Shown after logging and when committing to the week.
    public var why: String
    /// The line the widget leads with when this habit is furthest behind.
    public var nudge: String
    /// HealthKit activity name used when the habit is logged by hand (nil = can't be logged by tap).
    public var logsAs: String?

    public var id: String { key }

    public init(key: String, name: String, goal: Double, source: HabitSource, minMinutes: Double = 0,
                pillars: [String], why: String, nudge: String, logsAs: String? = nil) {
        self.key = key; self.name = name; self.goal = goal; self.source = source
        self.minMinutes = minMinutes; self.pillars = pillars; self.why = why
        self.nudge = nudge; self.logsAs = logsAs
    }
}

public struct MeasurementDefinition: Codable, Equatable, Identifiable, Sendable {
    public enum Entry: String, Codable, Sendable { case stepper, timedCount }

    public var key: String          // also the column name in checkins.csv
    public var name: String
    public var unit: String
    public var pillar: String
    public var entry: Entry
    public var step: Double
    public var min: Double
    public var max: Double
    public var lowerIsBetter: Bool
    /// Seconds for a timed count (the pop-up test).
    public var timerSeconds: Int
    /// How often it is worth repeating, in days.
    public var cadenceDays: Int
    /// "Best first thing, before coffee."
    public var hint: String
    /// One line on how to measure the same way every time.
    public var protocolLine: String
    /// What the number does and doesn't mean.
    public var honestLabel: String
    /// Habits shown beside the result when it moves.
    public var relatedHabits: [String]

    public var id: String { key }

    public init(key: String, name: String, unit: String, pillar: String, entry: Entry, step: Double,
                min: Double, max: Double, lowerIsBetter: Bool, timerSeconds: Int = 0, cadenceDays: Int = 7,
                hint: String, protocolLine: String, honestLabel: String, relatedHabits: [String]) {
        self.key = key; self.name = name; self.unit = unit; self.pillar = pillar; self.entry = entry
        self.step = step; self.min = min; self.max = max; self.lowerIsBetter = lowerIsBetter
        self.timerSeconds = timerSeconds; self.cadenceDays = cadenceDays; self.hint = hint
        self.protocolLine = protocolLine; self.honestLabel = honestLabel; self.relatedHabits = relatedHabits
    }
}

public struct GoalDefinition: Codable, Equatable, Sendable {
    public var title: String        // "Surf at 60"
    public var eventName: String    // "Surf camp"
    public var eventLine: String    // "the day you turn 60"
    /// yyyy-MM-dd
    public var targetDate: String
    /// yyyy-MM-dd; the left end of the horizon line.
    public var startDate: String

    public init(title: String, eventName: String, eventLine: String, targetDate: String, startDate: String) {
        self.title = title; self.eventName = eventName; self.eventLine = eventLine
        self.targetDate = targetDate; self.startDate = startDate
    }
}

/// Everything about the plan that is a choice, not code: goal, habits, measurements,
/// and which Health workout types count as what.
public struct SurfConfig: Codable, Equatable, Sendable {
    public var goal: GoalDefinition
    public var habits: [HabitDefinition]
    public var measurements: [MeasurementDefinition]
    /// HealthKit activity name (camelCase, e.g. "functionalStrengthTraining") to the type written
    /// in workouts.csv. Anything not listed is written as its own lower-case name.
    public var workoutTypeMap: [String: String]
    /// Habits are counted over this many days, ending today (the Mac dashboard uses 7).
    public var habitWindowDays: Int

    public init(goal: GoalDefinition, habits: [HabitDefinition], measurements: [MeasurementDefinition],
                workoutTypeMap: [String: String], habitWindowDays: Int = 7) {
        self.goal = goal; self.habits = habits; self.measurements = measurements
        self.workoutTypeMap = workoutTypeMap; self.habitWindowDays = habitWindowDays
    }

    public func habit(_ key: String) -> HabitDefinition? { habits.first { $0.key == key } }
    public func measurement(_ key: String) -> MeasurementDefinition? { measurements.first { $0.key == key } }

    /// The type written to workouts.csv for a HealthKit activity name.
    public func csvType(forActivity name: String) -> String {
        if let mapped = workoutTypeMap[name] { return mapped }
        return Self.lowercaseWords(name)
    }

    /// "highIntensityIntervalTraining" -> "high intensity interval training"; "walking" -> "walking".
    static func lowercaseWords(_ camel: String) -> String {
        var out = ""
        for ch in camel {
            if ch.isUppercase, !out.isEmpty { out.append(" ") }
            out.append(contentsOf: ch.lowercased())
        }
        return out
    }

    public static let `default` = SurfConfig(
        goal: GoalDefinition(title: "Surf at 60", eventName: "Surf camp", eventLine: "the day you turn 60",
                             targetDate: "2028-07-02", startDate: "2026-09-01"),
        habits: [
            HabitDefinition(key: "lift", name: "Lift", goal: 2, source: .workouts(types: ["strength"]),
                            pillars: ["strength", "power"], why: "Lifting builds your strength.",
                            nudge: "Lift today", logsAs: "traditionalStrengthTraining"),
            HabitDefinition(key: "row", name: "Row", goal: 2, source: .workouts(types: ["rowing"]),
                            pillars: ["cardio"], why: "Rows build your cardio.",
                            nudge: "Row today", logsAs: "rowing"),
            HabitDefinition(key: "yoga", name: "Yoga", goal: 3, source: .workouts(types: ["yoga"]),
                            pillars: ["mobility", "power"], why: "Yoga builds your mobility and your pop-up.",
                            nudge: "Yoga today", logsAs: "yoga"),
            HabitDefinition(key: "active", name: "Active", goal: 250, source: .exerciseMinutes,
                            pillars: ["body", "cardio"], why: "Active minutes move your waist and your cardio.",
                            nudge: "Move today"),
            HabitDefinition(key: "plan", name: "Plan", goal: 5, source: .planDays,
                            pillars: ["body"], why: "On-plan days move your waist.",
                            nudge: "On plan today"),
        ],
        measurements: [
            MeasurementDefinition(
                key: "waist_in", name: "Waist", unit: "in", pillar: "body", entry: .stepper, step: 0.25,
                min: 20, max: 70, lowerIsBetter: true,
                hint: "Best first thing, before coffee",
                protocolLine: "Tape level with the navel, relaxed, same time of day.",
                honestLabel: "One measure of body composition, not the whole picture.",
                relatedHabits: ["plan", "active"]),
            MeasurementDefinition(
                key: "popups_30s", name: "Pop-ups in 30 s", unit: "", pillar: "power", entry: .timedCount, step: 1,
                min: 0, max: 60, lowerIsBetter: false, timerSeconds: 30,
                hint: "Once you\u{2019}re warmed up",
                protocolLine: "Same surface each time. Chest to the floor, count each full pop-up.",
                honestLabel: "Specific to surfing, not a general power test.",
                relatedHabits: ["lift", "yoga"]),
            MeasurementDefinition(
                key: "sit_to_rise", name: "Sit-to-rise", unit: "", pillar: "mobility", entry: .stepper, step: 0.5,
                min: 0, max: 10, lowerIsBetter: false,
                hint: "Anytime, on a clear floor",
                protocolLine: "Start at 10. Minus 1 per hand, knee or forearm used; minus 0.5 for a wobble.",
                honestLabel: "Also reflects leg strength and balance, not mobility alone.",
                relatedHabits: ["yoga"]),
        ],
        workoutTypeMap: [
            "yoga": "yoga",
            "rowing": "rowing",
            "traditionalStrengthTraining": "strength",
            "functionalStrengthTraining": "strength",
        ]
    )
}
