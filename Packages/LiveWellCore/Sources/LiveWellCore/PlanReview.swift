import Foundation

// The biweekly plan review: two weeks of adherence per habit, each pillar's 4-week trend, and at
// most one proposed change. The rules are deliberately simple (version 1) and never scold.

public enum PlanReview {
    public struct HabitWeeks: Equatable, Sendable {
        public var key: String
        public var name: String
        public var goal: Double
        /// The earlier week, then the latest week. Nil = not measured that week.
        public var weeks: [Double?]
        public var pillars: [String]
        /// A note for each week whose target was changed by that week's commitment
        /// ("0 planned, Vacation"); nil for a usual week.
        public var planned: [String?]
        public init(key: String, name: String, goal: Double, weeks: [Double?], pillars: [String], planned: [String?] = [nil, nil]) {
            self.key = key; self.name = name; self.goal = goal; self.weeks = weeks; self.pillars = pillars; self.planned = planned
        }
        /// A week with a changed target was planned that way: it is never a miss, and it isn't
        /// evidence for a permanent change either.
        var hasPlannedWeek: Bool { planned.contains { $0 != nil } }
        var metBoth: Bool { !hasPlannedWeek && weeks.count == 2 && weeks.allSatisfy { ($0 ?? -1) >= goal } }
        var missedBoth: Bool { !hasPlannedWeek && weeks.count == 2 && weeks.allSatisfy { $0 != nil && $0! < goal } }
    }

    public enum Trend: String, Codable, Sendable { case up, flat, down, unknown }

    public struct PillarTrend: Equatable, Sendable {
        public var key: String
        public var label: String
        public var trend: Trend
        /// The value about four weeks ago and now.
        public var from: Double?
        public var to: Double?
        public var goal: Double?
        /// The goal after this one, when the Mac's settings name one.
        public var nextGoal: Double?
        /// The current value has passed the goal.
        public var reached: Bool
        public init(key: String, label: String, trend: Trend, from: Double? = nil, to: Double? = nil,
                    goal: Double? = nil, nextGoal: Double? = nil, reached: Bool = false) {
            self.key = key; self.label = label; self.trend = trend; self.from = from; self.to = to
            self.goal = goal; self.nextGoal = nextGoal; self.reached = reached
        }
    }

    public struct Proposal: Codable, Equatable, Sendable {
        /// "habit", "pillar", or "none" (stay the course).
        public var kind: String
        public var key: String
        public var name: String
        public var from: Double
        public var to: Double
        /// "Raise Row from 2 to 3 a week?"
        public var headline: String
        /// One or two plain sentences with the real numbers behind it.
        public var reason: String

        public var isChange: Bool { kind != "none" }

        public static func stay(_ reason: String) -> Proposal {
            Proposal(kind: "none", key: "", name: "", from: 0, to: 0, headline: "Stay the course.", reason: reason)
        }
    }

    /// What the reader chose, saved for the morning run to explain. File: app/plan_review.json.
    public struct Decision: Codable, Equatable, Sendable {
        public var date: String
        public var section: String
        public var proposal: Proposal
        /// "accept", "not_now", "no", or "stay" (nothing was proposed).
        public var decision: String
        public var reason: String
        /// What the review showed, in plain lines, so the explanation can cite real numbers.
        public var evidence: [String]
        public var at: String
        public init(date: String, section: String, proposal: Proposal, decision: String, reason: String,
                    evidence: [String], at: String) {
            self.date = date; self.section = section; self.proposal = proposal; self.decision = decision
            self.reason = reason; self.evidence = evidence; self.at = at
        }
    }

    public static let file = "app/plan_review.json"

    /// A modest step up: one more session, or about 10% more minutes (to the nearest 5).
    public static func stepUp(_ goal: Double) -> Double {
        goal > 20 ? ((goal * 1.1) / 5).rounded() * 5 : goal + 1
    }

    /// A smaller target: one fewer session (never below 1), or about 20% fewer minutes (nearest 10).
    public static func stepDown(_ goal: Double) -> Double {
        goal > 20 ? max(10, ((goal * 0.8) / 10).rounded() * 10) : max(1, goal - 1)
    }

    static func n(_ v: Double?) -> String { v.map(CheckinsFile.number) ?? "not measured" }

    /// At most one change. The rules, first match wins:
    /// 1. a habit met both weeks while a pillar it feeds stayed flat: a modest step up;
    /// 2. a habit missed both weeks: a smaller target;
    /// 3. a pillar reached its goal and a next goal is known: offer it;
    /// 4. otherwise stay the course.
    public static func propose(habits: [HabitWeeks], pillars: [PillarTrend]) -> Proposal {
        for habit in habits where habit.metBoth {
            guard let flat = pillars.first(where: { habit.pillars.contains($0.key) && !$0.reached && ($0.trend == .flat || $0.trend == .down) }) else { continue }
            let to = stepUp(habit.goal)
            return Proposal(kind: "habit", key: habit.key, name: habit.name, from: habit.goal, to: to,
                            headline: "Raise \(habit.name) from \(n(habit.goal)) to \(n(to))?",
                            reason: "You met \(habit.name) both weeks (\(n(habit.weeks[0])) and \(n(habit.weeks[1])) against \(n(habit.goal))), "
                                + "and \(flat.label) hasn't moved in four weeks (\(n(flat.from)) to \(n(flat.to))). A little more may be what moves it.")
        }
        for habit in habits where habit.missedBoth {
            let to = stepDown(habit.goal)
            guard to < habit.goal else { continue }
            return Proposal(kind: "habit", key: habit.key, name: habit.name, from: habit.goal, to: to,
                            headline: "Set \(habit.name) to \(n(to)) for now?",
                            reason: "\(habit.name) came in at \(n(habit.weeks[0])) and \(n(habit.weeks[1])) against \(n(habit.goal)). "
                                + "A target you hit builds more than one you miss; it can go back up later.")
        }
        for pillar in pillars where pillar.reached {
            guard let goal = pillar.goal, let next = pillar.nextGoal, next != goal else { continue }
            return Proposal(kind: "pillar", key: pillar.key, name: pillar.label, from: goal, to: next,
                            headline: "\(pillar.label) reached \(n(goal)). Make \(n(next)) the goal?",
                            reason: "\(pillar.label) is at \(n(pillar.to)), past the goal of \(n(goal)).")
        }
        let moving = pillars.filter { $0.trend == .up }.map(\.label)
        if habits.contains(where: \.hasPlannedWeek), moving.isEmpty {
            return .stay("One of these weeks was planned differently, so there isn't a fair pattern to act on yet.")
        }
        return .stay(moving.isEmpty ? "Nothing in the last two weeks calls for a change."
                                    : "\(moving.joined(separator: ", ")) \(moving.count == 1 ? "is" : "are") moving. The plan is working; keep it.")
    }

    /// The 4-week trend from dated readings (yyyy-MM-dd, any order).
    /// - span: the distance from start to goal; a change under 2% of it counts as flat.
    public static func trend(history: [(date: String, value: Double)], today: String, lowerIsBetter: Bool, span: Double)
        -> (trend: Trend, from: Double?, to: Double?) {
        let points = history.filter { $0.date <= today }.sorted { $0.date < $1.date }
        guard let last = points.last else { return (.unknown, nil, nil) }
        guard let cutoff = DayMath.adding(-28, to: today), let recent = DayMath.adding(-14, to: today) else { return (.unknown, nil, last.value) }
        // The reading from about four weeks ago; failing that, the oldest one if it is at least two weeks old.
        guard let then = points.last(where: { $0.date <= cutoff }) ?? points.first(where: { $0.date <= recent }) else {
            return (.unknown, nil, last.value)
        }
        let change = (last.value - then.value) * (lowerIsBetter ? -1 : 1)
        let threshold = max(abs(span) * 0.02, 0.0001)
        return (change > threshold ? .up : (change < -threshold ? .down : .flat), then.value, last.value)
    }

    /// True when a review is due: none yet, or the last one was 13 or more days ago.
    public static func isDue(lastReview: String?, today: String) -> Bool {
        guard let lastReview, let a = DayMath.date(lastReview), let b = DayMath.date(today) else { return true }
        return b.timeIntervalSince(a) >= 13 * 86_400
    }
}

/// Changes one number in a JSON file's text and leaves everything else (order, spacing, comments
/// in string fields) exactly as it was. Used for the goal values in the Mac's settings.json.
public enum JSONText {
    /// The text with the number at `path` replaced, or nil when the path isn't there.
    public static func setting(_ value: Double, at path: [String], in text: String) -> String? {
        guard let range = valueRange(path, in: text, from: text.startIndex) else { return nil }
        return text.replacingCharacters(in: range, with: CheckinsFile.number(value))
    }

    public static func number(at path: [String], in text: String) -> Double? {
        valueRange(path, in: text, from: text.startIndex).flatMap { Double(text[$0]) }
    }

    static func skipSpace(_ text: String, _ i: inout String.Index) {
        while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
    }

    /// `i` is at an opening quote; returns the string's contents and leaves `i` after the closing quote.
    static func readString(_ text: String, _ i: inout String.Index) -> String? {
        guard i < text.endIndex, text[i] == "\"" else { return nil }
        var out = ""
        i = text.index(after: i)
        while i < text.endIndex {
            let ch = text[i]
            i = text.index(after: i)
            if ch == "\"" { return out }
            if ch == "\\", i < text.endIndex { out.append(text[i]); i = text.index(after: i) } else { out.append(ch) }
        }
        return nil
    }

    /// Leaves `i` just past the value that starts at `i`.
    static func skipValue(_ text: String, _ i: inout String.Index) {
        skipSpace(text, &i)
        guard i < text.endIndex else { return }
        switch text[i] {
        case "\"": _ = readString(text, &i)
        case "{", "[":
            var depth = 0
            while i < text.endIndex {
                let ch = text[i]
                if ch == "\"" { _ = readString(text, &i); continue }
                if ch == "{" || ch == "[" { depth += 1 }
                if ch == "}" || ch == "]" { depth -= 1 }
                i = text.index(after: i)
                if depth == 0 { return }
            }
        default:
            while i < text.endIndex, !",}]".contains(text[i]), !text[i].isWhitespace { i = text.index(after: i) }
        }
    }

    static func valueRange(_ path: [String], in text: String, from start: String.Index) -> Range<String.Index>? {
        var i = start
        skipSpace(text, &i)
        guard let key = path.first else {
            let begin = i
            skipValue(text, &i)
            return begin..<i
        }
        guard i < text.endIndex, text[i] == "{" else { return nil }
        i = text.index(after: i)
        while i < text.endIndex {
            skipSpace(text, &i)
            if i < text.endIndex, text[i] == "," { i = text.index(after: i); continue }
            guard i < text.endIndex, text[i] != "}" else { return nil }
            guard let name = readString(text, &i) else { return nil }
            skipSpace(text, &i)
            guard i < text.endIndex, text[i] == ":" else { return nil }
            i = text.index(after: i)
            if name == key { return valueRange(Array(path.dropFirst()), in: text, from: i) }
            skipValue(text, &i)
        }
        return nil
    }
}
