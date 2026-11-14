import Foundation

// Wealth's rituals: short ceremonies around a holding's earnings and leadership, each ending by
// tying back to the reasons for owning it. "What to watch" the day before earnings, a "Still
// true?" check after them, and a leadership check when the person at the wheel changes.

public struct EarningsDate: Codable, Equatable, Sendable {
    public var ticker: String
    /// yyyy-MM-dd
    public var date: String
    /// "bmo" before the market opens, "amc" after the close, "dmh" during hours, or nil.
    public var hour: String?

    public init(ticker: String, date: String, hour: String? = nil) { self.ticker = ticker; self.date = date; self.hour = hour }

    /// "before the open", "after the close"
    public var when: String? {
        switch hour {
        case "bmo": return "before the open"
        case "amc": return "after the close"
        case "dmh": return "during market hours"
        default: return nil
        }
    }
}

/// Written the day before earnings: what he is watching, and what would make him doubt.
public struct WatchNote: Codable, Equatable, Sendable {
    public var ticker: String
    /// The earnings date it was written for.
    public var earnings: String
    /// The things to watch he picked for this report.
    public var watching: [String]
    /// "What result would make you doubt it, as opposed to just disappoint you?"
    public var doubt: String
    public var written: String

    public init(ticker: String, earnings: String, watching: [String], doubt: String, written: String) {
        self.ticker = ticker; self.earnings = earnings; self.watching = watching; self.doubt = doubt; self.written = written
    }
}

/// A "Still true?" check: each reason and each deal-breaker judged against the latest evidence.
public struct StillTrueCheck: Codable, Equatable, Sendable {
    public enum ReasonState: String, Codable, CaseIterable, Sendable {
        case yes, unsure, no
        public var label: String { self == .yes ? "Still true" : (self == .unsure ? "Not sure" : "No longer true") }
    }
    public enum BreakerState: String, Codable, CaseIterable, Sendable {
        case clear, tested, hit
        public var label: String { self == .clear ? "Not hit" : (self == .tested ? "Tested" : "Hit") }
    }
    public struct Reason: Codable, Equatable, Sendable { public var text: String; public var state: ReasonState
        public init(text: String, state: ReasonState) { self.text = text; self.state = state } }
    public struct Breaker: Codable, Equatable, Sendable { public var text: String; public var state: BreakerState
        public init(text: String, state: BreakerState) { self.text = text; self.state = state } }

    public var ticker: String
    public var date: String
    /// The earnings date that prompted it (nil when he ran it on his own).
    public var earnings: String?
    public var reasons: [Reason]
    public var dealBreakers: [Breaker]
    public var note: String

    public init(ticker: String, date: String, earnings: String?, reasons: [Reason], dealBreakers: [Breaker], note: String) {
        self.ticker = ticker; self.date = date; self.earnings = earnings; self.reasons = reasons
        self.dealBreakers = dealBreakers; self.note = note
    }

    /// What the board shows after this check, and the one thing that is next.
    public var outcome: (status: Wealth.Status, next: String, line: String) {
        let total = reasons.count, holding = reasons.filter { $0.state == .yes }.count
        if let hit = dealBreakers.first(where: { $0.state == .hit }) {
            return (.dealBreaker, "A deal-breaker was hit", "A deal-breaker was hit: \(hit.text)")
        }
        if let gone = reasons.first(where: { $0.state == .no }) {
            return (.dealBreaker, "A reason is no longer true", "A reason is no longer true: \(gone.text)")
        }
        if let tested = dealBreakers.first(where: { $0.state == .tested }) {
            return (.check(tested.text), "Tested, not hit: keep an eye on it", "\(holding) of \(total) reasons still true. One deal-breaker tested, not hit: \(tested.text)")
        }
        if let unsure = reasons.first(where: { $0.state == .unsure }) {
            return (.check(unsure.text), "One reason to check", "\(holding) of \(total) reasons still true. One to check: \(unsure.text)")
        }
        return (.stillTrue, "Still true as of \(DayMath.dateline(date).dropFirst(5))", "All \(total) reasons still true. No deal-breaker hit.")
    }
}

/// The framework's values filters, re-checked when something changes (a new chief executive).
public struct ValuesCheck: Codable, Equatable, Sendable {
    public enum Answer: String, Codable, CaseIterable, Sendable {
        case yes, unsure, no
        public var label: String { self == .yes ? "Yes" : (self == .unsure ? "Not sure" : "No") }
    }
    public var ticker: String
    public var date: String
    /// What prompted it ("New chief executive").
    public var trigger: String
    public var customer: Answer
    public var world: Answer
    public var leadership: Answer
    public var note: String

    public init(ticker: String, date: String, trigger: String, customer: Answer, world: Answer, leadership: Answer, note: String) {
        self.ticker = ticker; self.date = date; self.trigger = trigger; self.customer = customer
        self.world = world; self.leadership = leadership; self.note = note
    }

    public static let questions: [(key: String, title: String, asks: String)] = [
        ("customer", "Customer alignment", "Does it get rich by making its customers successful, not by trapping them?"),
        ("world", "World impact", "Does the business itself make things better, or at least do no harm?"),
        ("leadership", "Leadership trust", "Do you trust the values of the person at the wheel?"),
    ]

    public var answers: [Answer] { [customer, world, leadership] }

    /// "All three hold." / "Leadership trust: not sure." / "Leadership trust: no. Your framework says to stop here."
    public var line: String {
        let named = zip(Self.questions, answers)
        if let failed = named.first(where: { $0.1 == .no }) { return "\(failed.0.title): no. Your framework says a company that fails a values filter is a stop." }
        let unsure = named.filter { $0.1 == .unsure }.map { $0.0.title }
        return unsure.isEmpty ? "All three hold." : "\(unsure.joined(separator: ", ")): not sure yet."
    }
}

/// Everything the Wealth rituals record. File: app/checks.json, read by the morning run.
public struct WealthRecord: Codable, Equatable, Sendable {
    public var watch: [WatchNote] = []
    public var checks: [StillTrueCheck] = []
    public var values: [ValuesCheck] = []
    public init() {}
    public static let file = "app/checks.json"

    public func latestCheck(_ ticker: String) -> StillTrueCheck? { checks.filter { $0.ticker == ticker }.max { $0.date < $1.date } }
    public func latestValues(_ ticker: String) -> ValuesCheck? { values.filter { $0.ticker == ticker }.max { $0.date < $1.date } }
    public func note(_ ticker: String, earnings: String) -> WatchNote? { watch.last { $0.ticker == ticker && $0.earnings == earnings } }
}

public enum WealthRituals {
    /// The morning run can supply dates the price service doesn't have. File: newsletter/wealth/calendar.json.
    public static let calendarFile = "newsletter/wealth/calendar.json"

    /// The next report on or after today.
    public static func next(_ dates: [EarningsDate], _ ticker: String, today: String) -> EarningsDate? {
        dates.filter { $0.ticker == ticker && $0.date >= today }.min { $0.date < $1.date }
    }

    /// The most recent report before today.
    public static func last(_ dates: [EarningsDate], _ ticker: String, today: String) -> EarningsDate? {
        dates.filter { $0.ticker == ticker && $0.date < today }.max { $0.date < $1.date }
    }

    /// "What to watch" is due the day before a report and on the day itself, until it is written.
    public static func watchDue(_ dates: [EarningsDate], _ record: WealthRecord, ticker: String, today: String) -> EarningsDate? {
        guard let report = next(dates, ticker, today: today), let dayBefore = DayMath.adding(-1, to: report.date),
              today >= dayBefore, record.note(ticker, earnings: report.date) == nil else { return nil }
        return report
    }

    /// It can be written early: from two weeks before the report.
    public static func watchOpen(_ dates: [EarningsDate], ticker: String, today: String) -> EarningsDate? {
        guard let report = next(dates, ticker, today: today), let opens = DayMath.adding(-14, to: report.date), today >= opens else { return nil }
        return report
    }

    /// "Still true?" is due from the day after a report for three weeks, until a check is recorded for it.
    public static func checkDue(_ dates: [EarningsDate], _ record: WealthRecord, ticker: String, today: String) -> EarningsDate? {
        guard let report = last(dates, ticker, today: today), let closes = DayMath.adding(21, to: report.date), today <= closes,
              !record.checks.contains(where: { $0.ticker == ticker && ($0.earnings == report.date || $0.date > report.date) }) else { return nil }
        return report
    }

    /// Merges two lists of dates; the same ticker and date appears once, keeping an hour if either has one.
    public static func merge(_ a: [EarningsDate], _ b: [EarningsDate]) -> [EarningsDate] {
        var out: [String: EarningsDate] = [:]
        for d in a + b {
            let key = d.ticker + d.date
            if let have = out[key], have.hour != nil { continue }
            out[key] = d
        }
        return out.values.sorted { ($0.date, $0.ticker) < ($1.date, $1.ticker) }
    }
}
