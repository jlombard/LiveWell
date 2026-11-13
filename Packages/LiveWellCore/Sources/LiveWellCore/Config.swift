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
    /// SF Symbol for the tile and the widgets (nil = a plain circle).
    public var symbol: String?
    /// A second source of sessions counted with the workouts, one per day it has an entry
    /// ("fitclub" = days with an ARX main set in fitclub/sets.json, as the Mac counts Lift).
    public var alsoCounts: String?

    public var id: String { key }

    public init(key: String, name: String, goal: Double, source: HabitSource, minMinutes: Double = 0,
                pillars: [String], why: String, nudge: String, logsAs: String? = nil, symbol: String? = nil,
                alsoCounts: String? = nil) {
        self.key = key; self.name = name; self.goal = goal; self.source = source
        self.minMinutes = minMinutes; self.pillars = pillars; self.why = why
        self.nudge = nudge; self.logsAs = logsAs; self.symbol = symbol; self.alsoCounts = alsoCounts
    }

    /// The extra session source, with the built-in one for configs saved before it was configurable.
    public var extraSource: String? { alsoCounts ?? (key == "lift" ? "fitclub" : nil) }

    /// The symbol to draw, with the built-in ones for configs saved before symbols were configurable.
    public var symbolName: String {
        if let symbol, !symbol.isEmpty { return symbol }
        return ["lift": "dumbbell.fill", "row": "figure.rower", "yoga": "figure.yoga", "active": "figure.walk",
                "plan": "fork.knife"][key] ?? "circle"
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

/// One part of life the app covers: Health today; Money and Family later. A section has a name,
/// an icon and an accent, and optionally a goal, habits, measurements and a dashboard. A section
/// with none of those is just a feed of cards in the Report.
public struct SectionDefinition: Codable, Equatable, Identifiable, Sendable {
    public var key: String          // "health"; what issues, cards, votes and kept answers carry
    public var name: String         // "Health"
    public var icon: String         // SF Symbol
    public var accent: String       // "#5DB0F0"
    public var goal: GoalDefinition?
    public var habits: [HabitDefinition]
    public var measurements: [MeasurementDefinition]
    /// Whether Today shows this section's habit tiles and progress bars.
    public var dashboard: Bool
    /// Pillar goals the app has set (by an accepted plan review), by pillar key. Pillars not listed
    /// keep the goal in the Mac's settings.json.
    public var pillarGoals: [String: Double]

    public var id: String { key }

    public init(key: String, name: String, icon: String, accent: String, goal: GoalDefinition? = nil,
                habits: [HabitDefinition] = [], measurements: [MeasurementDefinition] = [], dashboard: Bool = false,
                pillarGoals: [String: Double] = [:]) {
        self.key = key; self.name = name; self.icon = icon; self.accent = accent; self.goal = goal
        self.habits = habits; self.measurements = measurements; self.dashboard = dashboard; self.pillarGoals = pillarGoals
    }

    enum CodingKeys: String, CodingKey { case key, name, icon, accent, goal, habits, measurements, dashboard, pillarGoals }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? key.prefix(1).uppercased() + key.dropFirst()
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "circle"
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? SectionDefinition.defaultAccent
        goal = try c.decodeIfPresent(GoalDefinition.self, forKey: .goal)
        habits = try c.decodeIfPresent([HabitDefinition].self, forKey: .habits) ?? []
        measurements = try c.decodeIfPresent([MeasurementDefinition].self, forKey: .measurements) ?? []
        dashboard = try c.decodeIfPresent(Bool.self, forKey: .dashboard) ?? false
        pillarGoals = try c.decodeIfPresent([String: Double].self, forKey: .pillarGoals) ?? [:]
    }

    public static let healthKey = "health"
    public static let defaultAccent = "#5DB0F0"
}

/// One accepted change to the plan, kept so the plan's history can be read back.
public struct PlanVersion: Codable, Equatable, Identifiable, Sendable {
    /// yyyy-MM-dd the change was accepted.
    public var date: String
    public var section: String
    /// "habit" or "pillar"
    public var kind: String
    public var key: String
    public var from: Double
    public var to: Double
    /// One sentence: what changed and why it was proposed.
    public var summary: String
    public var id: String { date + kind + key }

    public init(date: String, section: String, kind: String, key: String, from: Double, to: Double, summary: String) {
        self.date = date; self.section = section; self.kind = kind; self.key = key
        self.from = from; self.to = to; self.summary = summary
    }
}

/// Everything about the plan that is a choice, not code: the sections (each with its goal, habits
/// and measurements), which Health workout types count as what, and the plan's history.
///
/// `goal`, `habits` and `measurements` read and write the dashboard section, so the screens that
/// show one goal keep working while the config itself is section-first.
public struct SurfConfig: Codable, Equatable, Sendable {
    public var sections: [SectionDefinition]
    /// HealthKit activity name (camelCase, e.g. "functionalStrengthTraining") to the type written
    /// in workouts.csv. Anything not listed is written as its own lower-case name.
    public var workoutTypeMap: [String: String]
    /// Habits are counted over this many days, ending today (the Mac dashboard uses 7).
    public var habitWindowDays: Int
    /// Accepted plan changes, oldest first.
    public var planHistory: [PlanVersion]

    public init(sections: [SectionDefinition], workoutTypeMap: [String: String], habitWindowDays: Int = 7,
                planHistory: [PlanVersion] = []) {
        self.sections = sections; self.workoutTypeMap = workoutTypeMap
        self.habitWindowDays = habitWindowDays; self.planHistory = planHistory
    }

    /// One Health section holding this goal, these habits and these measurements.
    public init(goal: GoalDefinition, habits: [HabitDefinition], measurements: [MeasurementDefinition],
                workoutTypeMap: [String: String], habitWindowDays: Int = 7) {
        self.init(sections: [SectionDefinition(key: SectionDefinition.healthKey, name: "Health", icon: "figure.surfing",
                                               accent: SectionDefinition.defaultAccent, goal: goal, habits: habits,
                                               measurements: measurements, dashboard: true)],
                  workoutTypeMap: workoutTypeMap, habitWindowDays: habitWindowDays)
    }

    enum CodingKeys: String, CodingKey { case sections, workoutTypeMap, habitWindowDays, planHistory, goal, habits, measurements }

    /// Reads the section-first file, or the older file with goal, habits and measurements at the
    /// top level (they become the Health section).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let map = try c.decodeIfPresent([String: String].self, forKey: .workoutTypeMap) ?? SurfConfig.default.workoutTypeMap
        let days = try c.decodeIfPresent(Int.self, forKey: .habitWindowDays) ?? 7
        if let sections = try c.decodeIfPresent([SectionDefinition].self, forKey: .sections), !sections.isEmpty {
            self.init(sections: sections, workoutTypeMap: map, habitWindowDays: days,
                      planHistory: try c.decodeIfPresent([PlanVersion].self, forKey: .planHistory) ?? [])
        } else {
            self.init(goal: try c.decodeIfPresent(GoalDefinition.self, forKey: .goal) ?? SurfConfig.default.goal,
                      habits: try c.decodeIfPresent([HabitDefinition].self, forKey: .habits) ?? SurfConfig.default.habits,
                      measurements: try c.decodeIfPresent([MeasurementDefinition].self, forKey: .measurements) ?? SurfConfig.default.measurements,
                      workoutTypeMap: map, habitWindowDays: days)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sections, forKey: .sections)
        try c.encode(workoutTypeMap, forKey: .workoutTypeMap)
        try c.encode(habitWindowDays, forKey: .habitWindowDays)
        try c.encode(planHistory, forKey: .planHistory)
    }

    // MARK: sections

    public func section(_ key: String) -> SectionDefinition? { sections.first { $0.key == key } }

    /// The section's display name; an unknown key shows as itself, capitalised.
    public func sectionName(_ key: String) -> String {
        section(key)?.name ?? key.prefix(1).uppercased() + key.dropFirst()
    }

    /// Index of the section Today's dashboard shows: the first with a dashboard, else the first.
    var dashboardIndex: Int? { sections.firstIndex { $0.dashboard } ?? (sections.isEmpty ? nil : 0) }
    public var dashboardSection: SectionDefinition? { dashboardIndex.map { sections[$0] } }

    public var goal: GoalDefinition {
        get { dashboardSection?.goal ?? GoalDefinition(title: dashboardSection?.name ?? "LiveWell", eventName: "", eventLine: "", targetDate: "", startDate: "") }
        set { if let i = dashboardIndex { sections[i].goal = newValue } }
    }
    public var habits: [HabitDefinition] {
        get { dashboardSection?.habits ?? [] }
        set { if let i = dashboardIndex { sections[i].habits = newValue } }
    }
    public var measurements: [MeasurementDefinition] {
        get { dashboardSection?.measurements ?? [] }
        set { if let i = dashboardIndex { sections[i].measurements = newValue } }
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
                            nudge: "Lift today", logsAs: "traditionalStrengthTraining", symbol: "dumbbell.fill", alsoCounts: "fitclub"),
            HabitDefinition(key: "row", name: "Row", goal: 2, source: .workouts(types: ["rowing"]),
                            pillars: ["cardio"], why: "Rows build your cardio.",
                            nudge: "Row today", logsAs: "rowing", symbol: "figure.rower"),
            HabitDefinition(key: "yoga", name: "Yoga", goal: 3, source: .workouts(types: ["yoga"]),
                            pillars: ["mobility", "power"], why: "Yoga builds your mobility and your pop-up.",
                            nudge: "Yoga today", logsAs: "yoga", symbol: "figure.yoga"),
            HabitDefinition(key: "active", name: "Active", goal: 250, source: .exerciseMinutes,
                            pillars: ["body", "cardio"], why: "Active minutes move your waist and your cardio.",
                            nudge: "Move today", symbol: "figure.walk"),
            HabitDefinition(key: "plan", name: "Plan", goal: 5, source: .planDays,
                            pillars: ["body"], why: "On-plan days move your waist.",
                            nudge: "On plan today", symbol: "fork.knife"),
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
