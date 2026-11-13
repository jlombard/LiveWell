import Foundation

// Weekly commitment overrides: "Commit to the week" defaults to the usual habit goals, and any
// habit's target can be changed for that week only (rowing off on vacation, a stretch week).
// Permanent changes still go through the biweekly review.

public struct HabitCommitment: Codable, Equatable, Sendable {
    /// This week's target (0 = off this week).
    public var target: Double
    /// The habit's usual goal when the week was committed.
    public var usual: Double
    /// Vacation, Travel, Rest or recovery, Busy week, Other (optional).
    public var reason: String?

    public init(target: Double, usual: Double, reason: String? = nil) {
        self.target = target; self.usual = usual; self.reason = reason
    }

    public var changed: Bool { target != usual }
    public var isOff: Bool { target == 0 && usual > 0 }
}

/// One committed week. File: app/commitments.json (a list, oldest first). The week runs 7 days
/// from the day it is committed; a mid-week change is a new record from that day to the same end.
public struct WeekRecord: Codable, Equatable, Sendable {
    public var week_start: String
    public var week_end: String
    public var habits: [String: HabitCommitment]

    public init(week_start: String, week_end: String, habits: [String: HabitCommitment]) {
        self.week_start = week_start; self.week_end = week_end; self.habits = habits
    }

    public func covers(_ day: String) -> Bool { week_start <= day && day <= week_end }
    /// Any habit set below its usual goal.
    public var isLighter: Bool { habits.values.contains { $0.target < $0.usual } }
}

public enum Commitments {
    public static let file = "app/commitments.json"
    public static let reasons = ["Vacation", "Travel", "Rest or recovery", "Busy week", "Other"]

    /// Sessions and plan days step by 1, active minutes by 25.
    public static func step(_ habit: HabitDefinition) -> Double { habit.source == .exerciseMinutes ? 25 : 1 }
    /// Plan days can't pass 7; nothing else has a ceiling.
    public static func ceiling(_ habit: HabitDefinition) -> Double? { habit.source == .planDays ? 7 : nil }

    public static func stepped(_ target: Double, by direction: Int, habit: HabitDefinition) -> Double {
        let next = max(0, target + Double(direction) * step(habit))
        return ceiling(habit).map { min($0, next) } ?? next
    }

    /// The week in force on a day: the most recently written record that covers it.
    public static func active(_ records: [WeekRecord], on day: String) -> WeekRecord? {
        records.last { $0.covers(day) }
    }

    /// A new 7-day week starting today. Habits not in `targets` keep their usual goal.
    public static func commit(_ records: [WeekRecord], today: String, habits: [HabitDefinition],
                              targets: [String: HabitCommitment]) -> [WeekRecord] {
        var week: [String: HabitCommitment] = [:]
        for habit in habits {
            let chosen = targets[habit.key]
            let target = chosen?.target ?? habit.goal
            week[habit.key] = HabitCommitment(target: target, usual: habit.goal, reason: target == habit.goal ? nil : chosen?.reason)
        }
        let record = WeekRecord(week_start: today, week_end: DayMath.adding(6, to: today) ?? today, habits: week)
        return records.filter { $0.week_start != today } + [record]
    }

    /// A change made during the week (from Today): applies from today to the same week end. With no
    /// week in force, it starts one today.
    public static func change(_ records: [WeekRecord], today: String, habits: [HabitDefinition],
                              key: String, target: Double, reason: String?) -> [WeekRecord] {
        guard let habit = habits.first(where: { $0.key == key }) else { return records }
        var week = active(records, on: today)
            ?? commit([], today: today, habits: habits, targets: [:])[0]
        week.habits[key] = HabitCommitment(target: target, usual: habit.goal, reason: target == habit.goal ? nil : reason)
        week.week_start = today
        return records.filter { $0.week_start != today } + [week]
    }

    static func amount(_ value: Double, _ habit: HabitDefinition) -> String {
        CheckinsFile.number(value) + (habit.source == .exerciseMinutes ? " minutes" : "")
    }

    /// "Off this week · Vacation", "1 this week · usually 2", or nil when it is the usual target.
    public static func rowText(_ c: HabitCommitment, habit: HabitDefinition) -> String? {
        guard c.changed else { return nil }
        if c.target == 0 { return "Off this week" + (c.reason.map { " · \($0)" } ?? "") }
        return "\(amount(c.target, habit)) this week · usually \(CheckinsFile.number(c.usual))" + (c.reason.map { " · \($0)" } ?? "")
    }

    /// "Committed. A lighter week, still pointed at the water." or "Five habits. One goal."
    public static func closingLine(_ week: WeekRecord) -> String {
        if week.isLighter { return "A lighter week, still pointed at the water." }
        let f = NumberFormatter(); f.numberStyle = .spellOut
        let n = (f.string(from: NSNumber(value: week.habits.count)) ?? "\(week.habits.count)").capitalized
        return "\(n) habits. One goal."
    }

    /// "Row is back on Monday the 23rd." for each lowered habit, in the habits' order.
    public static func comeBack(_ week: WeekRecord, habits: [HabitDefinition]) -> [String] {
        guard let day = DayMath.adding(1, to: week.week_end), let dayNumber = Int(day.suffix(2)) else { return [] }
        let lowered = habits.filter { h in week.habits[h.key].map { $0.target < $0.usual } ?? false }
        guard !lowered.isEmpty else { return [] }
        let names = lowered.map(\.name)
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return ["\(list) \(names.count == 1 ? "is" : "are") back \(lowered.allSatisfy { week.habits[$0.key]?.target == 0 } ? "" : "to usual ")on \(DayMath.weekdayName(day)) the \(ordinal(dayNumber))."]
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
