import Foundation

/// data.json as the Mac's build.py writes it. Everything optional that could be absent,
/// so a new field or a missing one never breaks the app.
public struct DashboardData: Codable, Equatable, Sendable {
    public struct Pillar: Codable, Equatable, Identifiable, Sendable {
        public var key: String
        public var label: String
        public var desc: String?
        public var value: Double?
        public var display: String?
        public var from: Double?
        public var goal: Double?
        public var progress: Double?
        public var reached: Bool?
        public var as_of: String?
        public var from_label: String?
        public var goal_label: String?
        public var id: String { key }
    }

    public struct Habit: Codable, Equatable, Identifiable, Sendable {
        public var key: String
        public var value: Double?
        public var goal: Double?
        public var met: Bool?
        public var unit: String?
        public var id: String { key }
    }

    public var date: String?
    public var generated: String?
    public var title: String?
    public var today: String?
    public var pillars: [Pillar]
    public var habits: [Habit]

    public static func decode(_ data: Data) throws -> DashboardData {
        try JSONDecoder().decode(DashboardData.self, from: data)
    }
}

/// One habit as the app shows it.
public struct HabitStatus: Codable, Equatable, Identifiable, Sendable {
    public var key: String
    public var name: String
    public var value: Double?      // nil = not measured
    public var goal: Double
    public var provenance: Provenance
    public var id: String { key }

    public var met: Bool { (value ?? 0) >= goal && value != nil }
    /// 0...1, how much of the goal is done.
    public var fraction: Double { goal > 0 ? min(1, (value ?? 0) / goal) : 0 }

    public init(key: String, name: String, value: Double?, goal: Double, provenance: Provenance) {
        self.key = key; self.name = name; self.value = value; self.goal = goal; self.provenance = provenance
    }
}

public enum HabitCounter {
    /// Local start of the day `days - 1` before `now`'s day: the window is that day through today.
    public static func windowStart(now: Date, days: Int, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
    }

    /// Counts each habit over the window ending today.
    /// - workouts: rows as written to workouts.csv (type already mapped).
    /// - exerciseMinutes: per-day totals; nil when Health gave nothing (shows "not measured").
    /// - mac: data.json, used for habits the app can't count itself (plan days).
    public static func statuses(config: SurfConfig, workouts: [WorkoutRow], exerciseMinutes: [DatedValue]?,
                                mac: DashboardData?, now: Date, calendar: Calendar) -> [HabitStatus] {
        let start = windowStart(now: now, days: config.habitWindowDays, calendar: calendar)
        return config.habits.map { habit in
            switch habit.source {
            case .workouts(let types):
                let n = workouts.filter {
                    $0.start >= start && $0.start <= now && types.contains($0.type) && $0.minutes >= habit.minMinutes
                }.count
                return HabitStatus(key: habit.key, name: habit.name, value: Double(n), goal: habit.goal, provenance: .measured)
            case .exerciseMinutes:
                guard let exerciseMinutes else {
                    return HabitStatus(key: habit.key, name: habit.name, value: nil, goal: habit.goal, provenance: .missing)
                }
                let sum = exerciseMinutes.filter { $0.date >= start && $0.date <= now }.reduce(0) { $0 + $1.value }
                return HabitStatus(key: habit.key, name: habit.name, value: sum.rounded(), goal: habit.goal, provenance: .measured)
            case .planDays:
                let fromMac = mac?.habits.first { $0.key == habit.key }
                return HabitStatus(key: habit.key, name: habit.name, value: fromMac?.value,
                                   goal: habit.goal, provenance: fromMac?.value == nil ? .missing : .manual)
            }
        }
    }

    /// The unmet habit with the least of its goal done; nil when everything is met.
    /// Ties go to the order in the config. Habits with no reading are skipped.
    public static func furthestBehind(_ statuses: [HabitStatus]) -> HabitStatus? {
        statuses.filter { !$0.met && $0.value != nil }.min { $0.fraction < $1.fraction }
    }
}

/// What the lock-screen widget needs, written by the app into the shared App Group container.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Icon: Codable, Equatable, Sendable {
        public var key: String
        public var name: String
        public var met: Bool
        public init(key: String, name: String, met: Bool) { self.key = key; self.name = name; self.met = met }
    }
    public var line: String
    public var icons: [Icon]
    public var activeMinutes: Double?
    public var activeGoal: Double
    public var updated: Date

    public static let fileName = "widget.json"
    public static let placeholder = WidgetSnapshot(
        line: "Surf at 60",
        icons: SurfConfig.default.habits.map { Icon(key: $0.key, name: $0.name, met: false) },
        activeMinutes: nil, activeGoal: 250, updated: Date(timeIntervalSince1970: 0))

    public init(line: String, icons: [Icon], activeMinutes: Double?, activeGoal: Double, updated: Date) {
        self.line = line; self.icons = icons; self.activeMinutes = activeMinutes
        self.activeGoal = activeGoal; self.updated = updated
    }

    /// Line 1 is the Mac's Today line when data.json is from today; otherwise the nudge for the
    /// habit furthest behind, so the widget is never stale advice.
    public static func make(config: SurfConfig, statuses: [HabitStatus], mac: DashboardData?,
                            todayString: String, now: Date) -> WidgetSnapshot {
        var line = config.goal.title
        if let mac, mac.date == todayString, let today = mac.today, !today.isEmpty {
            line = shorten(today)
        } else if let behind = HabitCounter.furthestBehind(statuses), let habit = config.habit(behind.key) {
            line = habit.nudge
        }
        let active = statuses.first { $0.key == "active" }
        return WidgetSnapshot(line: line,
                              icons: statuses.map { Icon(key: $0.key, name: $0.name, met: $0.met) },
                              activeMinutes: active?.value, activeGoal: active?.goal ?? 250, updated: now)
    }

    /// "Row today." -> "Row today"; long lines keep their first sentence.
    public static func shorten(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = s.firstIndex(of: "."), s.distance(from: s.startIndex, to: dot) > 3 { s = String(s[..<dot]) }
        return s
    }
}

public enum GoalMath {
    static func day(_ string: String, calendar: Calendar) -> Date? {
        let p = string.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// Whole days from today to the target date (0 once it has passed).
    public static func daysLeft(goal: GoalDefinition, now: Date, calendar: Calendar) -> Int? {
        guard let target = day(goal.targetDate, calendar: calendar) else { return nil }
        let d = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: target).day ?? 0
        return max(0, d)
    }

    /// 0...1 along the horizon line from start date to target date.
    public static func horizon(goal: GoalDefinition, now: Date, calendar: Calendar) -> Double {
        guard let start = day(goal.startDate, calendar: calendar), let target = day(goal.targetDate, calendar: calendar),
              target > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / target.timeIntervalSince(start)))
    }

    public static func dayString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// What to say when a check-in number is revealed. Honest either way.
public struct Reveal: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case first, improved, steady, slipped }
    public var kind: Kind
    public var headline: String

    public static func make(measurement: MeasurementDefinition, value: Double,
                            previous: (date: String, value: Double)?,
                            baseline: (date: String, value: Double)?) -> Reveal {
        guard let previous else {
            return Reveal(kind: .first, headline: "Your starting point.")
        }
        let change = value - previous.value
        let better = measurement.lowerIsBetter ? change < 0 : change > 0
        let unit = measurement.unit.isEmpty ? "" : " \(measurement.unit)"
        let amount = CheckinsFile.number(abs(change))
        if change == 0 {
            return Reveal(kind: .steady, headline: "Holding at \(CheckinsFile.number(value))\(unit).")
        }
        let direction = change < 0 ? "down" : "up"
        if better {
            if let baseline, baseline.date < previous.date {
                let total = abs(value - baseline.value)
                return Reveal(kind: .improved,
                              headline: "\(CheckinsFile.number(total))\(unit) \(direction) since \(monthName(baseline.date)).")
            }
            return Reveal(kind: .improved, headline: "\(amount)\(unit) \(direction) since last time.")
        }
        return Reveal(kind: .slipped,
                      headline: "\(amount)\(unit) \(direction) from last time. One reading; the trend is what counts.")
    }

    static func monthName(_ day: String) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August",
                     "September", "October", "November", "December"]
        let p = day.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 && (1...12).contains(p[1]) ? names[p[1] - 1] : day
    }
}
