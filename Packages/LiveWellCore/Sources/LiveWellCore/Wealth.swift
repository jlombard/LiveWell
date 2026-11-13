import Foundation

// The Wealth section's numbers: holdings from a brokerage CSV, daily closes recorded on the
// phone, each holding's share of the account, and the week's change in percent. No live prices,
// no tickers scrolling, no red or green: money appears as one weekly percent.

public struct Holding: Codable, Equatable, Identifiable, Sendable {
    public var ticker: String
    public var shares: Double
    public var costBasis: Double?
    /// The company's name as the brokerage wrote it ("APPLE INC").
    public var name: String?
    public var id: String { ticker }

    public init(ticker: String, shares: Double, costBasis: Double? = nil, name: String? = nil) {
        self.ticker = ticker; self.shares = shares; self.costBasis = costBasis; self.name = name
    }

    /// "Apple" from "APPLE INC COM"; the ticker when there is no name.
    public var displayName: String {
        guard let name, !name.isEmpty else { return ticker }
        let drop: Set<String> = ["INC", "INC.", "CORP", "CORP.", "CORPORATION", "COM", "CO", "LTD", "PLC", "NV", "N.V.", "HOLDING", "HOLDINGS",
                                 "CLASS", "CL", "A", "B", "C", "CAP", "STK", "ADR", "SPONSORED", "NY", "REGISTRY", "SHS", "NEW", "THE"]
        let words = name.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        let kept = words.prefix { !drop.contains($0.uppercased()) }
        let chosen = kept.isEmpty ? Array(words.prefix(1)) : Array(kept)
        return chosen.map { $0.count <= 4 && $0 == $0.uppercased() && $0.count > 1 && !$0.contains(where: \.isLowercase) && ["ASML", "IBM", "AMD", "SAP"].contains($0)
            ? $0 : $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }
}

/// Reads a brokerage positions export. Only ticker, shares, cost basis and the security's name
/// are kept; account numbers, account names and everything else in the file are never stored.
public enum HoldingsCSV {
    static let tickerHeads = ["symbol", "ticker", "symbol/cusip", "security id", "security symbol"]
    static let sharesHeads = ["quantity", "shares", "qty", "share quantity"]
    static let costHeads = ["cost basis total", "cost basis", "total cost", "total cost basis", "cost"]
    static let nameHeads = ["description", "name", "security description", "security"]

    static func number(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    /// A stock or ETF ticker: 1 to 5 letters, optionally a class suffix (BRK.B). Money-market and
    /// cash lines (SPAXX**, "Pending Activity", CUSIPs) are left out.
    static func isTicker(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let first = parts.first, (1...5).contains(first.count) else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter && $0.isASCII && $0.isUppercase } }
    }

    public static func parse(_ text: String) -> [Holding] {
        var clean = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        // Some exports are tab-separated; read them the same way.
        if let firstLines = Optional(clean.prefix(2000)), firstLines.filter({ $0 == "\t" }).count > firstLines.filter({ $0 == "," }).count {
            clean = clean.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map { CSV.field(String($0)) }.joined(separator: ",") }
                .joined(separator: "\n")
        }
        let rows = CSV.parse(clean)
        // The header is the first row that names both a ticker column and a shares column.
        func column(_ row: [String], _ names: [String]) -> Int? {
            let lower = row.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            for name in names { if let i = lower.firstIndex(of: name) { return i } }
            return nil
        }
        guard let headerIndex = rows.firstIndex(where: { column($0, tickerHeads) != nil && column($0, sharesHeads) != nil }) else { return [] }
        let header = rows[headerIndex]
        let t = column(header, tickerHeads)!, q = column(header, sharesHeads)!
        let c = column(header, costHeads), n = column(header, nameHeads)
        var byTicker: [String: Holding] = [:], order: [String] = []
        for row in rows[(headerIndex + 1)...] where row.count > max(t, q) {
            let ticker = row[t].trimmingCharacters(in: .whitespaces).uppercased()
            guard isTicker(ticker), let shares = number(row[q]), shares > 0 else { continue }
            let cost = c.flatMap { $0 < row.count ? number(row[$0]) : nil }
            let name = n.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : nil }
            if var existing = byTicker[ticker] {   // the same holding in two lots or accounts
                existing.shares += shares
                if let cost { existing.costBasis = (existing.costBasis ?? 0) + cost }
                byTicker[ticker] = existing
            } else {
                byTicker[ticker] = Holding(ticker: ticker, shares: shares, costBasis: cost, name: name)
                order.append(ticker)
            }
        }
        return order.compactMap { byTicker[$0] }
    }
}

/// Daily closing prices, recorded by the app after each US close.
public struct PriceBook: Codable, Equatable, Sendable {
    /// ticker → yyyy-MM-dd → close
    public var closes: [String: [String: Double]] = [:]

    public init() {}

    public mutating func record(_ ticker: String, day: String, close: Double) {
        guard close > 0 else { return }
        closes[ticker, default: [:]][day] = close
    }

    /// The latest close on or before a day.
    public func close(_ ticker: String, onOrBefore day: String) -> (day: String, close: Double)? {
        guard let series = closes[ticker], let best = series.keys.filter({ $0 <= day }).max() else { return nil }
        return (best, series[best]!)
    }

    /// The earliest close on or after a day.
    public func close(_ ticker: String, onOrAfter day: String) -> (day: String, close: Double)? {
        guard let series = closes[ticker], let best = series.keys.filter({ $0 >= day }).min() else { return nil }
        return (best, series[best]!)
    }

    public var latestDay: String? { closes.values.compactMap { $0.keys.max() }.max() }
}

public enum Wealth {
    public static let sectionKey = "wealth"

    public enum Status: Equatable, Sendable {
        case stillTrue
        case check(String)       // "Next: check"
        case dealBreaker
        case notWritten          // "Write it"

        public var pill: String {
            switch self {
            case .stillTrue: return "Still true"
            case .check: return "Next: check"
            case .dealBreaker: return "Deal-breaker hit"
            case .notWritten: return "Write it"
            }
        }
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public var ticker: String
        public var name: String
        /// Share of the account by value, 0...1 (nil until there is a price).
        public var share: Double?
        public var status: Status
        /// The next thing that matters for this holding.
        public var next: String
        public var id: String { ticker }
    }

    /// The weekday before a day (Monday → Friday). Market holidays aren't known here.
    public static func previousTradingDay(_ day: String) -> String {
        var d = day
        repeat { d = DayMath.adding(-1, to: d) ?? d } while [1, 7].contains(DayMath.weekday(d) ?? 2)
        return d
    }

    /// The last weekday of the previous week: the close "this week" is measured from.
    public static func weekBase(_ today: String) -> String {
        guard let weekday = DayMath.weekday(today) else { return today }
        // Sunday = 1 ... Saturday = 7. Back to the most recent Friday strictly before this week's Monday.
        let sinceMonday = (weekday + 5) % 7
        return DayMath.adding(-(sinceMonday + 3), to: today) ?? today
    }

    /// Each holding's share of the account by value at its latest close.
    public static func shares(_ holdings: [Holding], _ book: PriceBook, today: String) -> [String: Double] {
        var values: [String: Double] = [:]
        for h in holdings { if let p = book.close(h.ticker, onOrBefore: today) { values[h.ticker] = h.shares * p.close } }
        let total = values.values.reduce(0, +)
        return total > 0 ? values.mapValues { $0 / total } : [:]
    }

    /// The change across holdings between two days, weighted by value (share counts × prices).
    /// Only holdings with a close at both ends are counted.
    static func change(_ holdings: [Holding], _ book: PriceBook, from: (String) -> (day: String, close: Double)?,
                       to today: String) -> (percent: Double, from: String)? {
        var then = 0.0, now = 0.0, earliest: String?
        for h in holdings {
            guard let start = from(h.ticker), let end = book.close(h.ticker, onOrBefore: today), end.day > start.day else { continue }
            then += h.shares * start.close; now += h.shares * end.close
            earliest = max(earliest ?? start.day, start.day)
        }
        guard then > 0, let earliest else { return nil }
        return ((now / then - 1) * 100, earliest)
    }

    /// The week's change in percent. Measured from the last close of the previous week; when the
    /// app has no close that old yet, from the first close it does have this week, and `since`
    /// names that day so the label can say so.
    public static func week(_ holdings: [Holding], _ book: PriceBook, today: String) -> (percent: Double, since: String?)? {
        let base = weekBase(today)
        if let full = change(holdings, book, from: { t in book.close(t, onOrBefore: base).flatMap { $0.day >= (DayMath.adding(-4, to: base) ?? base) ? $0 : nil } }, to: today) {
            return (full.percent, nil)
        }
        guard let partial = change(holdings, book, from: { book.close($0, onOrAfter: base) }, to: today) else { return nil }
        return (partial.percent, partial.from)
    }

    /// The latest day's change: the last close against the one before it.
    public static func day(_ holdings: [Holding], _ book: PriceBook, today: String) -> Double? {
        change(holdings, book, from: { t in
            guard let last = book.close(t, onOrBefore: today), let before = DayMath.adding(-1, to: last.day) else { return nil }
            return book.close(t, onOrBefore: before)
        }, to: today)?.percent
    }

    /// "+2.1%", "−0.4%", "0.0%". One decimal, a true minus sign.
    public static func percentText(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        let body = String(format: "%.1f", abs(rounded))
        return rounded > 0 ? "+\(body)%" : (rounded < 0 ? "\u{2212}\(body)%" : "0.0%")
    }

    /// The board: one row per holding, largest share first.
    /// - started: holdings whose reasons are being drafted, with how many of the nine lenses are done.
    public static func board(_ holdings: [Holding], _ book: PriceBook, today: String, written: Set<String> = [],
                             started: [String: Int] = [:]) -> [Row] {
        let share = shares(holdings, book, today: today)
        return holdings.map { h in
            let status: Status = written.contains(h.ticker) ? .stillTrue : .notWritten
            let next = status != .notWritten ? "Your reasons are written"
                : (started[h.ticker].map { "Started · \($0) of \(Lens.all.count) lenses done" } ?? "Write why you own it")
            return Row(ticker: h.ticker, name: h.displayName, share: share[h.ticker], status: status,
                       next: next)
        }.sorted { ($0.share ?? 0, $1.ticker) > ($1.share ?? 0, $0.ticker) }
    }

    /// The one thing that needs doing, or "All reasons still true."
    public static func next(_ rows: [Row]) -> String {
        if let hit = rows.first(where: { $0.status == .dealBreaker }) { return "Next: look at \(hit.name)" }
        if let check = rows.first(where: { if case .check = $0.status { return true } else { return false } }) { return "Next: check \(check.name)" }
        if let unwritten = rows.first(where: { $0.status == .notWritten }) { return "Next: write why you own \(unwritten.name)" }
        return "All reasons still true."
    }

    /// A note when one holding has drifted large. `limit` is a share, 0...1.
    public static func concentration(_ rows: [Row], limit: Double) -> String? {
        guard let top = rows.first, let share = top.share, share > limit, rows.count > 1 else { return nil }
        return "\(top.name) is \(Int((share * 100).rounded()))% of this account."
    }

    /// The morning run's view of the section. File: app/wealth.json. Shares of the account only:
    /// no share counts, no cost basis, no dollar amounts.
    public struct Summary: Codable, Equatable, Sendable {
        public struct Item: Codable, Equatable, Sendable {
            public var ticker: String; public var name: String; public var share_pct: Double?; public var status: String
        }
        public var updated: String
        public var holdings: [Item]
        public var week_pct: Double?
        /// Set when the week is measured from a day later than last week's close.
        public var week_since: String?
        public var prices_as_of: String?
        public var next: String

        public init(rows: [Row], week: (percent: Double, since: String?)?, pricesAsOf: String?, updated: String) {
            holdings = rows.map { Item(ticker: $0.ticker, name: $0.name, share_pct: $0.share.map { ($0 * 1000).rounded() / 10 }, status: $0.status.pill) }
            week_pct = week.map { ($0.percent * 10).rounded() / 10 }
            week_since = week?.since; prices_as_of = pricesAsOf; next = Wealth.next(rows); self.updated = updated
        }
    }
    public static let file = "app/wealth.json"
}
