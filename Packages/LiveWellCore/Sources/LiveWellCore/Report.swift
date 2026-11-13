import Foundation

// The Surf Report: one issue file per day in newsletter/issues/YYYY-MM-DD.json, written by the
// Mac's morning run (see engine/surf_report_guide.md for the schema). Everything decodes
// leniently: a field the app doesn't know, or one that is missing or the wrong shape, is
// dropped and the rest of the issue still shows.

extension KeyedDecodingContainer {
    /// The value if present and well-formed, otherwise nil. Never throws.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// A string, or a number written as one ("3/2", 299).
    func text(_ key: Key) -> String? {
        if let s = lenient(String.self, key) { return s }
        if let d = lenient(Double.self, key) { return ReportFigure.number(d) }
        return nil
    }
}

/// Decodes each element on its own, so one bad card or row doesn't lose the others.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element] = []
    private struct Skip: Decodable {}
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) { elements.append(element) }
            else { _ = try? container.decode(Skip.self) }
        }
    }
}

public struct ReportSource: Codable, Equatable, Sendable {
    /// "Author et al., {link}Title{/link}, Journal, Year."
    public var text: String
    public var url: String?

    public init(text: String, url: String? = nil) { self.text = text; self.url = url }

    /// The text before, inside and after the {link}…{/link} markers.
    public var parts: (before: String, link: String, after: String) {
        guard let open = text.range(of: "{link}"), let close = text.range(of: "{/link}"),
              open.upperBound <= close.lowerBound else { return (text, "", "") }
        return (String(text[..<open.lowerBound]), String(text[open.upperBound..<close.lowerBound]),
                String(text[close.upperBound...]))
    }

    public var plain: String { let p = parts; return p.before + p.link + p.after }
}

public struct ReportFigure: Decodable, Equatable, Sendable {
    public struct Point: Equatable, Sendable { public var label: String; public var value: Double }
    public struct Mark: Decodable, Equatable, Sendable { public var text: String; public var below: Bool? }
    public struct Pair: Equatable, Sendable, Decodable {
        public var label: String; public var from: Double; public var to: Double
    }
    public struct Tile: Equatable, Sendable { public var value: String; public var name: String; public var met: Bool }

    public var type: String
    public var alt: String?
    public var caption: String?
    // spark
    public var points: [Point] = []
    public var marks: [Int: Mark] = [:]
    public var dashLast = false
    // spark and scale
    public var min: Double?
    public var max: Double?
    // scale
    public var ticks: [Double] = []
    public var band: [Double] = []
    public var bandLabel: String?
    public var you: Double?
    public var youLabel: String?
    public var goal: Double?
    public var goalLabel: String?
    // pairs, tiles, svg
    public var rows: [Pair] = []
    public var items: [Tile] = []
    public var svg: String?

    enum Keys: String, CodingKey {
        case type, alt, caption, points, marks, dashLast, min, max, ticks, band, bandLabel
        case you, youLabel, goal, goalLabel, rows, items, svg
    }
    private enum TileKeys: String, CodingKey { case v, n, met }
    private struct RawTile: Decodable {
        var tile: Tile
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: TileKeys.self)
            tile = Tile(value: c.text(.v) ?? "", name: c.text(.n) ?? "", met: c.lenient(Bool.self, .met) ?? false)
        }
    }
    private struct RawPoint: Decodable {
        var point: Point
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            let label = (try? c.decode(String.self)) ?? ""
            point = Point(label: label, value: try c.decode(Double.self))
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        type = try c.decode(String.self, forKey: .type)
        alt = c.lenient(String.self, .alt)
        caption = c.lenient(String.self, .caption)
        points = c.lenient(LossyArray<RawPoint>.self, .points)?.elements.map(\.point) ?? []
        for (key, mark) in c.lenient([String: Mark].self, .marks) ?? [:] {
            if let i = Int(key) { marks[i] = mark }
        }
        dashLast = c.lenient(Bool.self, .dashLast) ?? false
        min = c.lenient(Double.self, .min); max = c.lenient(Double.self, .max)
        ticks = c.lenient([Double].self, .ticks) ?? []
        band = c.lenient([Double].self, .band) ?? []
        bandLabel = c.lenient(String.self, .bandLabel)
        you = c.lenient(Double.self, .you); youLabel = c.lenient(String.self, .youLabel)
        goal = c.lenient(Double.self, .goal); goalLabel = c.lenient(String.self, .goalLabel)
        rows = c.lenient(LossyArray<Pair>.self, .rows)?.elements ?? []
        items = c.lenient(LossyArray<RawTile>.self, .items)?.elements.map(\.tile) ?? []
        svg = c.lenient(String.self, .svg)
    }

    /// 554, 1,204, 28.4 (whole numbers without a decimal, thousands grouped).
    public static func number(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 {
            let n = Int(v), digits = String(abs(n))
            var out = ""
            for (i, ch) in digits.enumerated() {
                if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
                out.append(ch)
            }
            return (n < 0 ? "-" : "") + out
        }
        return CheckinsFile.number(v)
    }
}

public struct ReportCard: Decodable, Equatable, Identifiable, Sendable {
    public struct Try: Equatable, Sendable { public var label: String; public var text: String }
    public struct Recipe: Equatable, Sendable {
        public var ingredients: [String]; public var steps: [String]; public var copyText: String?
    }
    public struct Lesson: Equatable, Sendable {
        public var tag: String?; public var body: [String]; public var source: ReportSource?
    }
    public struct Quiz: Equatable, Sendable {
        public struct Option: Equatable, Sendable { public var text: String; public var right: Bool }
        public var options: [Option]; public var reveal: String
    }

    public var id: String
    public var kind: String
    public var label: String
    public var title: String
    public var pillar: String?
    public var tag: String?
    public var win: Bool
    public var why: String?
    public var body: [String]
    public var bullets: [String]
    public var figure: ReportFigure?
    public var figureAfter: ReportFigure?
    public var tryIt: Try?
    public var sub: String?
    public var source: ReportSource?
    public var recipe: Recipe?
    public var lesson: Lesson?
    public var quiz: Quiz?
    public var starters: [String]

    enum Keys: String, CodingKey {
        case id, kind, label, title, pillar, tag, win, why, body, bullets, figure, figureAfter
        case tryIt = "try", sub, source, recipe, lesson, quiz, starters
    }
    private enum Inner: String, CodingKey {
        case label, text, ingredients, steps, copyText, tag, body, source, options, reveal, t, right
    }
    private struct RawOption: Decodable {
        var option: Quiz.Option
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Inner.self)
            option = Quiz.Option(text: try c.decode(String.self, forKey: .t), right: c.lenient(Bool.self, .right) ?? false)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = c.lenient(String.self, .kind) ?? "you"
        title = c.lenient(String.self, .title) ?? ""
        id = c.lenient(String.self, .id) ?? RichText.plain(title)
        label = c.lenient(String.self, .label) ?? ""
        pillar = c.lenient(String.self, .pillar); tag = c.lenient(String.self, .tag)
        win = c.lenient(Bool.self, .win) ?? false
        why = c.lenient(String.self, .why)
        body = c.lenient([String].self, .body) ?? []
        bullets = c.lenient([String].self, .bullets) ?? []
        figure = c.lenient(ReportFigure.self, .figure)
        figureAfter = c.lenient(ReportFigure.self, .figureAfter)
        sub = c.lenient(String.self, .sub)
        source = c.lenient(ReportSource.self, .source)
        starters = c.lenient([String].self, .starters) ?? []
        if let t = try? c.nestedContainer(keyedBy: Inner.self, forKey: .tryIt), let text = t.lenient(String.self, .text) {
            tryIt = Try(label: t.lenient(String.self, .label) ?? "Try it", text: text)
        }
        if let r = try? c.nestedContainer(keyedBy: Inner.self, forKey: .recipe) {
            recipe = Recipe(ingredients: r.lenient([String].self, .ingredients) ?? [],
                            steps: r.lenient([String].self, .steps) ?? [], copyText: r.lenient(String.self, .copyText))
        }
        if let l = try? c.nestedContainer(keyedBy: Inner.self, forKey: .lesson) {
            lesson = Lesson(tag: l.lenient(String.self, .tag), body: l.lenient([String].self, .body) ?? [],
                            source: l.lenient(ReportSource.self, .source))
        }
        if let q = try? c.nestedContainer(keyedBy: Inner.self, forKey: .quiz) {
            let options = q.lenient(LossyArray<RawOption>.self, .options)?.elements.map(\.option) ?? []
            if !options.isEmpty { quiz = Quiz(options: options, reveal: q.lenient(String.self, .reveal) ?? "") }
        }
    }

    /// The Recipe box groups by this: the lesson's nutrient, "Fibre" folded into "Fiber".
    public var nutrient: String {
        let raw = (lesson?.tag ?? "").trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return "Other" }
        let name = raw.prefix(1).uppercased() + raw.dropFirst()
        return name == "Fibre" ? "Fiber" : name
    }

    /// The card as plain text, for the Go deeper chat (figures and buttons left out).
    public var plainText: String {
        var parts: [String] = [[label, pillar, tag].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")]
        parts.append(RichText.plain(title))
        if let why { parts.append(RichText.plain(why)) }
        parts += body.map(RichText.plain)
        parts += bullets.map { "- " + RichText.plain($0) }
        if let recipe {
            parts.append("You need:\n" + recipe.ingredients.map { "- " + $0 }.joined(separator: "\n"))
            parts.append("Do this:\n" + recipe.steps.map { "- " + $0 }.joined(separator: "\n"))
        }
        if let lesson {
            parts.append("Nutrition lesson" + (lesson.tag.map { " (\($0))" } ?? ""))
            parts += lesson.body.map(RichText.plain)
            if let s = lesson.source { parts.append("Source: " + s.plain) }
        }
        if let quiz {
            parts += quiz.options.map { "- " + $0.text + ($0.right ? " (correct)" : "") }
            parts.append(RichText.plain(quiz.reveal))
        }
        if let tryIt { parts.append(tryIt.label + ": " + RichText.plain(tryIt.text)) }
        if let sub { parts.append(RichText.plain(sub)) }
        if let source { parts.append("Source: " + source.plain) }
        return String(parts.filter { !$0.isEmpty }.joined(separator: "\n\n").prefix(4000))
    }
}

public struct ReportIssue: Decodable, Equatable, Identifiable, Sendable {
    public struct Plate: Equatable, Sendable { public var label: String; public var text: String }

    public var date: String
    public var issue: Int?
    public var intro: String?
    /// One paragraph about the reader and today's numbers, fed to the Go deeper chat.
    public var profile: String
    public var planGoal: Int?
    public var planDefinition: String?
    public var planStarters: [String]
    public var plate: Plate?
    public var cards: [ReportCard]

    public var id: String { date }

    enum Keys: String, CodingKey {
        case date, issue, intro, profile, cards, plate
        case planGoal = "plan_goal", planDefinition = "plan_definition", planStarters = "plan_starters"
    }
    private enum PlateKeys: String, CodingKey { case label, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        date = try c.decode(String.self, forKey: .date)
        issue = c.lenient(Int.self, .issue)
        intro = c.lenient(String.self, .intro)
        profile = c.lenient(String.self, .profile) ?? ""
        planGoal = c.lenient(Int.self, .planGoal)
        planDefinition = c.lenient(String.self, .planDefinition)
        planStarters = c.lenient([String].self, .planStarters) ?? []
        cards = c.lenient(LossyArray<ReportCard>.self, .cards)?.elements ?? []
        if let p = try? c.nestedContainer(keyedBy: PlateKeys.self, forKey: .plate), let text = p.lenient(String.self, .text) {
            plate = Plate(label: p.lenient(String.self, .label) ?? "Today's plate", text: text)
        } else if let text = c.lenient(String.self, .plate) {
            plate = Plate(label: "Today's plate", text: text)
        }
    }

    public static func decode(_ data: Data) throws -> ReportIssue {
        try JSONDecoder().decode(ReportIssue.self, from: data)
    }

    /// Cards that aren't the closing "You're caught up" card.
    public var contentCards: [ReportCard] { cards.filter { $0.kind != "end" } }
}

/// Past issues and every recipe, built from the issue files (the same index surf_report.py makes).
public struct ReportArchive: Equatable, Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public var date: String; public var issue: Int?; public var lead: String
        public var count: Int; public var recipes: Int
        public var id: String { date }
    }
    public struct RecipeEntry: Equatable, Identifiable, Sendable {
        public var date: String; public var card: ReportCard
        public var id: String { date + "_" + card.id }
    }

    /// Newest first.
    public var issues: [Entry] = []
    public var recipes: [RecipeEntry] = []

    public init() {}

    public init(issues all: [ReportIssue]) {
        for issue in all.sorted(by: { $0.date > $1.date }) {
            let cards = issue.contentCards
            let withRecipes = cards.filter { $0.recipe != nil }
            issues.append(Entry(date: issue.date, issue: issue.issue, lead: cards.first?.title ?? "",
                                count: cards.count, recipes: withRecipes.count))
            recipes += withRecipes.map { RecipeEntry(date: issue.date, card: $0) }
        }
    }

    /// Recipes grouped by nutrient, groups in alphabetical order, newest recipe first in each.
    public var recipeGroups: [(nutrient: String, recipes: [RecipeEntry])] {
        Dictionary(grouping: recipes) { $0.card.nutrient }
            .map { (nutrient: $0.key, recipes: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.nutrient < $1.nutrient }
    }
}

/// The small set of inline HTML the issues use: <em>, <b>, <span class="num">, <a href>, <br>.
public enum RichText {
    public struct Run: Equatable, Sendable {
        public var text: String
        public var emphasis = false
        public var bold = false
        public var number = false
        public var link: String?
        public init(text: String, emphasis: Bool = false, bold: Bool = false, number: Bool = false, link: String? = nil) {
            self.text = text; self.emphasis = emphasis; self.bold = bold; self.number = number; self.link = link
        }
    }

    static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'", "nbsp": "\u{00A0}",
        "ndash": "–", "mdash": "—", "hellip": "…", "rarr": "→", "times": "×", "deg": "°",
    ]

    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = "", rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let tail = rest[rest.index(after: amp)...]
            if let semi = tail.prefix(10).firstIndex(of: ";") {
                let name = String(tail[..<semi])
                var replacement = entities[name]
                if replacement == nil, name.hasPrefix("#") {
                    let digits = name.dropFirst()
                    let code = digits.hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                    replacement = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                }
                if let replacement { out += replacement; rest = tail[tail.index(after: semi)...]; continue }
            }
            out += "&"; rest = tail
        }
        return out + rest
    }

    public static func parse(_ html: String) -> [Run] {
        var runs: [Run] = []
        var em = 0, bold = 0, link: [String] = [], spans: [Bool] = []
        var rest = Substring(html)
        func emit(_ text: Substring) {
            guard !text.isEmpty else { return }
            runs.append(Run(text: unescape(String(text)), emphasis: em > 0, bold: bold > 0,
                            number: spans.contains(true), link: link.last))
        }
        while let open = rest.firstIndex(of: "<") {
            guard let close = rest[open...].firstIndex(of: ">") else { break }
            let inside = rest[rest.index(after: open)..<close]
            let isTag = inside.first.map { $0.isLetter || $0 == "/" } ?? false
            guard isTag else {   // a bare "<", as in "< 6 hours"
                emit(rest[...open]); rest = rest[rest.index(after: open)...]; continue
            }
            emit(rest[..<open])
            let closing = inside.hasPrefix("/")
            let name = inside.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
            switch name {
            case "em", "i": em = max(0, em + (closing ? -1 : 1))
            case "b", "strong": bold = max(0, bold + (closing ? -1 : 1))
            case "span": if closing { _ = spans.popLast() } else { spans.append(inside.contains("num")) }
            case "a":
                if closing { _ = link.popLast() } else { link.append(attribute("href", in: inside) ?? "") }
            case "br": runs.append(Run(text: "\n"))
            default: break
            }
            rest = rest[rest.index(after: close)...]
        }
        emit(rest)
        return runs
    }

    static func attribute(_ name: String, in tag: Substring) -> String? {
        guard let r = tag.range(of: name + "=") else { return nil }
        let after = tag[r.upperBound...]
        guard let quote = after.first, quote == "\"" || quote == "'" else {
            return String(after.prefix { !$0.isWhitespace })
        }
        return unescape(String(after.dropFirst().prefix { $0 != quote }))
    }

    public static func plain(_ html: String) -> String {
        parse(html).map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
