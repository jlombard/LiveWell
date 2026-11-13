import Foundation

// "Name the company": a weekly puzzle card in Build Wealth. One mystery public company, its
// revenue mix from the latest annual report as a treemap. Six guesses; each miss unlocks a clue
// and shows how close the guess was (sector, industry, niche).

public struct Puzzle: Decodable, Equatable, Sendable {
    public struct Segment: Equatable, Sendable { public var value: Double; public var label: String }
    public struct Bar: Decodable, Equatable, Sendable { public var label: String; public var pct: Double }
    public struct Clue: Decodable, Equatable, Sendable {
        public var title: String
        public var text: String
        /// An optional split shown as one stacked bar ("U.S. 72.7%, Canada 13.4%…").
        public var bars: [Bar]

        enum Keys: String, CodingKey { case title, text, bars }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            title = c.lenient(String.self, .title) ?? ""
            text = c.lenient(String.self, .text) ?? ""
            bars = c.lenient(LossyArray<Bar>.self, .bars)?.elements ?? []
        }
    }

    public var number: Int?
    /// The company's name exactly as in the catalog ("Costco").
    public var answer: String
    /// The full name shown at the reveal ("Costco Wholesale").
    public var full: String
    public var period: String
    public var total: String
    public var caption: String?
    public var segments: [Segment]
    public var clues: [Clue]
    public var why: String
    public var lesson: String
    public var sources: [ReportSource]

    enum Keys: String, CodingKey { case number, answer, full, period, total, cap, caption, segments, seg, clues, why, lesson, source, sources }

    private struct RawSegment: Decodable {
        var segment: Segment
        init(from decoder: Decoder) throws {
            // [116788, "Packaged food & household"] or {"value": …, "label": …}
            if var list = try? decoder.unkeyedContainer() {
                let value = try list.decode(Double.self)
                segment = Segment(value: value, label: (try? list.decode(String.self)) ?? "")
            } else {
                enum K: String, CodingKey { case value, label }
                let c = try decoder.container(keyedBy: K.self)
                segment = Segment(value: try c.decode(Double.self, forKey: .value), label: c.lenient(String.self, .label) ?? "")
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        answer = try c.decode(String.self, forKey: .answer)
        number = c.lenient(Int.self, .number)
        full = c.lenient(String.self, .full) ?? answer
        period = c.lenient(String.self, .period) ?? ""
        total = c.lenient(String.self, .total) ?? ""
        caption = c.lenient(String.self, .caption) ?? c.lenient(String.self, .cap)
        segments = (c.lenient(LossyArray<RawSegment>.self, .segments) ?? c.lenient(LossyArray<RawSegment>.self, .seg))?
            .elements.map(\.segment).filter { $0.value > 0 } ?? []
        clues = c.lenient(LossyArray<Clue>.self, .clues)?.elements ?? []
        why = c.lenient(String.self, .why) ?? ""
        lesson = c.lenient(String.self, .lesson) ?? ""
        sources = c.lenient(LossyArray<ReportSource>.self, .sources)?.elements ?? c.lenient(ReportSource.self, .source).map { [$0] } ?? []
    }

    public static let maxGuesses = 6

    /// A puzzle can only be played when its answer is a company the catalog knows.
    public var isPlayable: Bool { PuzzleCatalog.tree[answer] != nil && !segments.isEmpty }

    // MARK: the treemap

    public struct Tile: Equatable, Sendable {
        public var label: String
        /// Share of the total, 0...100.
        public var percent: Double
        /// Position in a unit square (0...1).
        public var x, y, w, h: Double
        /// Too small for its label: show the number only.
        public var small: Bool { w < 0.18 || h < 0.16 }
    }

    /// Slices the square largest first, across when the remaining space is wide and down when it is tall.
    public var tiles: [Tile] {
        let total = segments.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }
        var out: [Tile] = []
        func place(_ s: Segment, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            out.append(Tile(label: s.label, percent: s.value / total * 100, x: x, y: y, w: w, h: h))
        }
        func lay(_ items: ArraySlice<Segment>, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            guard let first = items.first else { return }
            if items.count == 1 { place(first, x, y, w, h); return }
            let f = first.value / items.reduce(0) { $0 + $1.value }
            // The square is drawn 4:3, so compare in drawn proportions.
            if w * 4 >= h * 3 * 0.75 { place(first, x, y, w * f, h); lay(items.dropFirst(), x + w * f, y, w * (1 - f), h) }
            else { place(first, x, y, w, h * f); lay(items.dropFirst(), x, y + h * f, w, h * (1 - f)) }
        }
        lay(segments[...], 0, 0, 1, 1)
        return out
    }
}

/// The companies that can be guessed, with a simplified three-level tree for closeness
/// (sector, industry, niche). It is a game aid, not an official classification.
public enum PuzzleCatalog {
    public static let tree: [String: [String]] = [
        "Costco": ["Consumer staples", "Retail", "Warehouse clubs"],
        "BJ's Wholesale": ["Consumer staples", "Retail", "Warehouse clubs"],
        "Walmart": ["Consumer staples", "Retail", "Big-box & discount"],
        "Target": ["Consumer staples", "Retail", "Big-box & discount"],
        "Dollar General": ["Consumer staples", "Retail", "Big-box & discount"],
        "Kroger": ["Consumer staples", "Retail", "Grocery stores"],
        "Procter & Gamble": ["Consumer staples", "Household products", "Home & personal care"],
        "Colgate-Palmolive": ["Consumer staples", "Household products", "Home & personal care"],
        "Coca-Cola": ["Consumer staples", "Beverages", "Soft drinks"],
        "PepsiCo": ["Consumer staples", "Beverages", "Soft drinks"],
        "Amazon": ["Consumer discretionary", "Retail", "E-commerce"],
        "eBay": ["Consumer discretionary", "Retail", "E-commerce"],
        "Home Depot": ["Consumer discretionary", "Retail", "Home improvement"],
        "Lowe's": ["Consumer discretionary", "Retail", "Home improvement"],
        "McDonald's": ["Consumer discretionary", "Restaurants", "Fast food"],
        "Yum Brands": ["Consumer discretionary", "Restaurants", "Fast food"],
        "Chipotle": ["Consumer discretionary", "Restaurants", "Fast casual"],
        "Starbucks": ["Consumer discretionary", "Restaurants", "Coffee"],
        "Tesla": ["Consumer discretionary", "Autos", "Electric vehicles"],
        "Ford": ["Consumer discretionary", "Autos", "Carmakers"],
        "Nike": ["Consumer discretionary", "Apparel", "Footwear"],
        "Apple": ["Technology", "Hardware", "Devices"],
        "Microsoft": ["Technology", "Software", "Platforms & cloud"],
        "Oracle": ["Technology", "Software", "Databases & cloud"],
        "Salesforce": ["Technology", "Software", "Business apps"],
        "Adobe": ["Technology", "Software", "Creative apps"],
        "IBM": ["Technology", "IT services", "Consulting & infrastructure"],
        "Nvidia": ["Technology", "Semiconductors", "Chip design"],
        "AMD": ["Technology", "Semiconductors", "Chip design"],
        "Broadcom": ["Technology", "Semiconductors", "Chip design"],
        "TSMC": ["Technology", "Semiconductors", "Foundry"],
        "ASML": ["Technology", "Semiconductors", "Chip equipment"],
        "Applied Materials": ["Technology", "Semiconductors", "Chip equipment"],
        "Alphabet": ["Communication", "Interactive media", "Search & ads"],
        "Meta": ["Communication", "Interactive media", "Social"],
        "Netflix": ["Communication", "Entertainment", "Streaming"],
        "Disney": ["Communication", "Entertainment", "Studios & parks"],
        "Visa": ["Financials", "Payments", "Card networks"],
        "Mastercard": ["Financials", "Payments", "Card networks"],
        "PayPal": ["Financials", "Payments", "Digital wallets"],
        "JPMorgan Chase": ["Financials", "Banks", "Big banks"],
        "Eli Lilly": ["Health care", "Pharma", "Drugmakers"],
        "Pfizer": ["Health care", "Pharma", "Drugmakers"],
        "UnitedHealth": ["Health care", "Insurance", "Health plans"],
        "Boeing": ["Industrials", "Aerospace", "Planes"],
        "UPS": ["Industrials", "Logistics", "Parcel delivery"],
        "FedEx": ["Industrials", "Logistics", "Parcel delivery"],
        "ExxonMobil": ["Energy", "Oil & gas", "Integrated"],
        "Chevron": ["Energy", "Oil & gas", "Integrated"],
    ]

    static let aliases: [String: String] = [
        "costco wholesale": "Costco", "google": "Alphabet", "facebook": "Meta", "jpmorgan": "JPMorgan Chase", "jp morgan": "JPMorgan Chase",
        "exxon": "ExxonMobil", "bjs": "BJ's Wholesale", "bj's": "BJ's Wholesale", "p&g": "Procter & Gamble", "lilly": "Eli Lilly",
        "coke": "Coca-Cola", "pepsi": "PepsiCo", "walt disney": "Disney", "mcdonalds": "McDonald's", "msft": "Microsoft", "aws": "Amazon",
        "yum": "Yum Brands",
    ]

    public static let names: [String] = tree.keys.sorted()

    static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Up to six companies containing what was typed, leaving out ones already guessed.
    public static func suggestions(_ typed: String, excluding: [String] = []) -> [String] {
        let s = fold(typed)
        guard !s.isEmpty else { return [] }
        // Names that start with what was typed come first, then names that contain it.
        var found = names.filter { $0.lowercased().hasPrefix(s) } + names.filter { !$0.lowercased().hasPrefix(s) && $0.lowercased().contains(s) }
        if let alias = aliases.first(where: { $0.key.hasPrefix(s) })?.value, !found.contains(alias) { found.insert(alias, at: 0) }
        return Array(found.filter { !excluding.contains($0) }.prefix(6))
    }

    /// The company a typed guess means: an alias, an exact name, or the only match.
    public static func resolve(_ typed: String) -> String? {
        let s = fold(typed)
        guard !s.isEmpty else { return nil }
        if let alias = aliases[s] { return alias }
        if let exact = names.first(where: { $0.lowercased() == s }) { return exact }
        let partial = names.filter { $0.lowercased().contains(s) }
        return partial.count == 1 ? partial[0] : nil
    }
}

/// One play of one puzzle.
public struct PuzzleGame: Codable, Equatable, Sendable {
    public var answer: String
    public var guesses: [String] = []

    public init(answer: String) { self.answer = answer }

    public var won: Bool { guesses.last == answer }
    public var finished: Bool { won || guesses.count >= Puzzle.maxGuesses }

    /// How many levels a guess shares with the answer, from the top: 0 to 3.
    public func closeness(_ guess: String) -> Int {
        guard let target = PuzzleCatalog.tree[answer], let mine = PuzzleCatalog.tree[guess] else { return 0 }
        var n = 0
        for i in 0..<3 { if mine[i] == target[i] { n += 1 } else { break } }
        return n
    }

    /// "Same sector: Consumer staples · not Beverages"
    public func hint(_ guess: String) -> String {
        if guess == answer { return "That is the company" }
        guard let mine = PuzzleCatalog.tree[guess] else { return "" }
        switch closeness(guess) {
        case 0: return "Not in \(mine[0])"
        case 1: return "Same sector: \(mine[0]) · not \(mine[1])"
        case 2: return "Same industry: \(mine[1]) · not \(mine[2])"
        default: return "Same niche, different company"
        }
    }

    public enum GuessResult: Equatable { case accepted, unknown, repeated(String), over }

    public mutating func guess(_ typed: String) -> GuessResult {
        if finished { return .over }
        guard let name = PuzzleCatalog.resolve(typed) else { return .unknown }
        if guesses.contains(name) { return .repeated(name) }
        guesses.append(name)
        return .accepted
    }

    /// Clues open one per miss; all of them once the game is over.
    public func cluesOpen(of total: Int) -> Int { finished ? total : min(guesses.count, total) }

    /// "Guess 3 of 6 · clue 3 unlocked"
    public func status(clues: Int) -> String {
        guard !finished else { return won ? "Solved in \(guesses.count) of \(Puzzle.maxGuesses)" : "The answer" }
        var s = "Guess \(guesses.count + 1) of \(Puzzle.maxGuesses)"
        if !guesses.isEmpty { s += clues >= guesses.count ? " · clue \(guesses.count + 1) unlocked" : " · no more clues" }
        return s
    }

    /// The result to share: black and white squares, no emoji.
    public func shareText(number: Int?) -> String {
        let rows = guesses.map { g -> String in
            let n = closeness(g)
            return String(repeating: "\u{25A0}", count: n) + String(repeating: "\u{25A1}", count: 3 - n)
        }
        let title = "Name the company" + (number.map { " No. \($0)" } ?? "")
        return "\(title)  \(won ? "\(guesses.count)" : "X")/\(Puzzle.maxGuesses)\n" + rows.joined(separator: "\n")
    }
}

/// Every puzzle played, kept on the phone.
public struct PuzzleStats: Codable, Equatable, Sendable {
    /// Puzzle id (the issue date) → the game.
    public var games: [String: PuzzleGame] = [:]

    public init() {}

    var finishedInOrder: [(id: String, game: PuzzleGame)] {
        games.filter { $0.value.finished }.sorted { $0.key < $1.key }.map { (id: $0.key, game: $0.value) }
    }
    public var played: Int { finishedInOrder.count }
    public var solved: Int { finishedInOrder.filter { $0.game.won }.count }
    /// Puzzles solved in a row, counting back from the most recent one finished.
    public var streak: Int { finishedInOrder.reversed().prefix { $0.game.won }.count }
    public var bestStreak: Int {
        var best = 0, run = 0
        for item in finishedInOrder { run = item.game.won ? run + 1 : 0; best = max(best, run) }
        return best
    }
    /// "Solved 5 of 6 · streak 3"
    public var line: String? {
        guard played > 0 else { return nil }
        return "Solved \(solved) of \(played)" + (streak > 1 ? " · streak \(streak)" : "")
    }
}
