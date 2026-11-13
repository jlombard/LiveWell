import Foundation

// "Why I own it": the reasons Joe has written for each holding, in the app's everyday words.
// The investment framework's own terms (thesis, pillars, break conditions, signals) stay in the
// framework document; this file maps between the two.

/// One holding's written reasons. File: app/reasons.json (a list), read by the morning run.
public struct Reasons: Codable, Equatable, Identifiable, Sendable {
    public var ticker: String
    public var name: String
    /// "I believe ASML will keep winning because…"
    public var belief: String
    public var reasons: [String]
    public var dealBreakers: [String]
    /// Things to watch.
    public var watch: [String]
    /// yyyy-MM-dd it was written or last changed.
    public var written: String
    /// "app" when written in Ask, "framework" when read from investment-framework.md.
    public var source: String
    public var id: String { ticker }

    public init(ticker: String, name: String, belief: String, reasons: [String], dealBreakers: [String], watch: [String],
                written: String, source: String) {
        self.ticker = ticker; self.name = name; self.belief = belief; self.reasons = reasons
        self.dealBreakers = dealBreakers; self.watch = watch; self.written = written; self.source = source
    }

    public static let file = "app/reasons.json"
}

/// The nine lenses of the guided conversation: the framework's eight playbooks plus Values.
public struct Lens: Equatable, Identifiable, Sendable {
    public var key: String
    /// The everyday name used in the app.
    public var name: String
    /// The framework's tag, for the morning run and for Go deeper when asked.
    public var tag: String
    /// What this lens asks, in a sentence.
    public var asks: String
    /// Where to look first.
    public var sources: String
    public var id: String { key }

    public static let all: [Lens] = [
        Lens(key: "problem", name: "Problem", tag: "P1",
             asks: "What problem does it solve, how big and urgent is it, and does the company make money by solving it?",
             sources: "the annual report's business description and segment revenue"),
        Lens(key: "model", name: "Business model", tag: "P2",
             asks: "Who exactly are the customers, what is the unfair advantage, and what is the next business it is betting on for growth?",
             sources: "the annual report, investor-day targets and the latest shareholder letter"),
        Lens(key: "users", name: "Users", tag: "P3",
             asks: "What do real users say unprompted, what can't they live without, and are complaints growing or shrinking?",
             sources: "forums and reviews, labelled as sentiment, never as fact"),
        Lens(key: "developers", name: "Developers", tag: "P4",
             asks: "Is the developer community growing, are its questions answered, and is there excitement or frustration about new releases?",
             sources: "developer forums, release notes and GitHub activity"),
        Lens(key: "supply", name: "Supply chain", tag: "P5",
             asks: "Who does it critically depend on, who depends on it, and where are the single points of failure or geopolitical exposure?",
             sources: "the annual report's risk factors and customer-concentration disclosures"),
        Lens(key: "smart", name: "Smart money", tag: "P6",
             asks: "Where are long-horizon investors and operators placing bets, and what does management dwell on that isn't revenue yet?",
             sources: "13F filings, corporate venture portfolios and earnings-call Q&A"),
        Lens(key: "ceiling", name: "Ceiling", tag: "P7",
             asks: "What do physics and economics say is possible here, how far is the company from that ceiling, and could a different approach leapfrog it?",
             sources: "published roadmaps and the scientific literature on limits"),
        Lens(key: "speed", name: "Speed", tag: "P8",
             asks: "How fast does it learn: how often do real improvements ship, how cheaply can it fail, and is the installed base a learning engine?",
             sources: "release history, R&D spending and measured improvements over time"),
        Lens(key: "values", name: "Values", tag: "V",
             asks: "Does it get rich by making customers successful, does the core business do good, and do you trust who is at the wheel?",
             sources: "the proxy statement (what executives are paid to achieve) and leadership's record"),
    ]

    public static func named(_ key: String) -> Lens? { all.first { $0.key == key } }
}

/// The draft that builds beside the conversation. Claude proposes lines; only lines Joe has
/// approved are in the draft, and he can reword or remove any of them.
public struct ReasonsDraft: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case belief, reason, dealBreaker = "deal_breaker", watch

        public var heading: String {
            switch self {
            case .belief: return "I believe"
            case .reason: return "Reasons"
            case .dealBreaker: return "Deal-breakers"
            case .watch: return "Things to watch"
            }
        }
    }
    public struct Line: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var kind: Kind
        public var text: String
        /// The lens it came from.
        public var lens: String?
        public init(id: String, kind: Kind, text: String, lens: String? = nil) {
            self.id = id; self.kind = kind; self.text = text; self.lens = lens
        }
    }

    public var ticker: String
    public var lines: [Line] = []
    public var lensesDone: [String] = []

    public init(ticker: String) { self.ticker = ticker }

    public func lines(_ kind: Kind) -> [Line] { lines.filter { $0.kind == kind } }

    /// Approving a belief replaces the one before it: there is one "I believe" line.
    public mutating func approve(_ kind: Kind, _ text: String, lens: String?, id: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !lines.contains(where: { $0.kind == kind && $0.text == clean }) else { return }
        if kind == .belief { lines.removeAll { $0.kind == .belief } }
        lines.append(Line(id: id, kind: kind, text: clean, lens: lens))
    }

    /// Ready to save: a belief, at least one reason and at least one deal-breaker.
    public var isComplete: Bool { !lines(.belief).isEmpty && !lines(.reason).isEmpty && !lines(.dealBreaker).isEmpty }

    public var missing: String? {
        var need: [String] = []
        if lines(.belief).isEmpty { need.append("an \u{201C}I believe\u{201D} line") }
        if lines(.reason).isEmpty { need.append("at least one reason") }
        if lines(.dealBreaker).isEmpty { need.append("at least one deal-breaker") }
        return need.isEmpty ? nil : "Still needed: " + need.joined(separator: ", ") + "."
    }

    public func reasons(name: String, today: String) -> Reasons? {
        guard isComplete else { return nil }
        return Reasons(ticker: ticker, name: name, belief: lines(.belief)[0].text, reasons: lines(.reason).map(\.text),
                       dealBreakers: lines(.dealBreaker).map(\.text), watch: lines(.watch).map(\.text), written: today, source: "app")
    }

    /// A draft to revise existing reasons from.
    public init(revising r: Reasons) {
        ticker = r.ticker
        var n = 0
        func add(_ kind: Kind, _ texts: [String]) -> [Line] { texts.map { n += 1; return Line(id: "r\(n)", kind: kind, text: $0) } }
        lines = add(.belief, [r.belief]) + add(.reason, r.reasons) + add(.dealBreaker, r.dealBreakers) + add(.watch, r.watch)
    }
}

/// Lines Claude proposes in a reply, marked so the app can offer each for approval:
/// `<propose kind="reason">Customers fund its research and own its equity.</propose>`
public enum Proposals {
    public struct Proposal: Equatable, Identifiable, Sendable {
        public var kind: ReasonsDraft.Kind
        public var text: String
        public var id: String { kind.rawValue + text }
    }

    /// The reply without its proposal tags, and the proposals in order. An unfinished tag (still
    /// streaming) is held back from the visible text.
    public static func split(_ reply: String) -> (text: String, proposals: [Proposal]) {
        var visible = "", proposals: [Proposal] = []
        var rest = Substring(reply)
        while let open = rest.range(of: "<propose") {
            visible += rest[..<open.lowerBound]
            guard let tagEnd = rest[open.upperBound...].firstIndex(of: ">"),
                  let close = rest[tagEnd...].range(of: "</propose>") else { rest = ""; break }
            let attributes = rest[open.upperBound..<tagEnd]
            let raw = RichText.attribute("kind", in: attributes) ?? ""
            let kind = ReasonsDraft.Kind(rawValue: raw.replacingOccurrences(of: "-", with: "_"))
                ?? (raw.contains("deal") ? .dealBreaker : nil)
            let text = rest[rest.index(after: tagEnd)..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if let kind, !text.isEmpty { proposals.append(Proposal(kind: kind, text: text)) }
            rest = rest[close.upperBound...]
        }
        visible += rest
        // Hide a tag that has only started to arrive.
        if let partial = visible.range(of: "<", options: .backwards), "<propose".hasPrefix(visible[partial.lowerBound...]) {
            visible = String(visible[..<partial.lowerBound])
        }
        while visible.contains("\n\n\n") { visible = visible.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return (visible.trimmingCharacters(in: .whitespacesAndNewlines), proposals)
    }
}

/// Reads theses out of investment-framework.md ("### ASML (ASML) …", "**Thesis:**", pillars,
/// "Thesis breaks if", "Key signals to monitor") into the app's words.
public enum FrameworkDoc {
    public static func reasons(in markdown: String, today: String) -> [Reasons] {
        var out: [Reasons] = []
        let lines = markdown.replacingOccurrences(of: "\u{2019}", with: "'").split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var i = 0
        func bullet(_ line: String) -> String? {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") { return String(t.dropFirst(2)) }
            if let dot = t.firstIndex(of: "."), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty {
                return t[t.index(after: dot)...].trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
        while i < lines.count {
            let line = lines[i]
            // "### ASML (ASML) — Initiated …"
            guard line.hasPrefix("### "), let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") else { i += 1; continue }
            let ticker = String(line[line.index(after: open)..<close])
            let name = line.dropFirst(4)[..<open].trimmingCharacters(in: .whitespaces)
            guard HoldingsCSV.isTicker(ticker) else { i += 1; continue }
            var belief = "", pillars: [String] = [], breaks: [String] = [], signals: [String] = []
            var mode = ""
            i += 1
            while i < lines.count, !lines[i].hasPrefix("### "), !lines[i].hasPrefix("## ") {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                let lower = t.lowercased()
                if lower.hasPrefix("**thesis:**") {
                    belief = String(t.dropFirst("**Thesis:**".count)).trimmingCharacters(in: .whitespaces); mode = ""
                } else if lower.hasPrefix("**key thesis pillars") { mode = "pillars" }
                else if lower.hasPrefix("**thesis breaks if") { mode = "breaks" }
                else if lower.hasPrefix("**key signals") { mode = "signals" }
                else if t.hasPrefix("**") || t.hasPrefix("|") { mode = "" }
                else if let b = bullet(t) {
                    // "A: Only company on earth…" loses its letter.
                    var text = b
                    if mode == "pillars", text.count > 3, text.dropFirst().hasPrefix(": ") { text = String(text.dropFirst(3)) }
                    switch mode {
                    case "pillars": pillars.append(text)
                    case "breaks": breaks.append(text)
                    case "signals": signals.append(text)
                    default: break
                    }
                }
                i += 1
            }
            if !belief.isEmpty {
                // "ASML will continue to win because…" reads as "I believe ASML will continue to win because…"
                let lead = belief.hasPrefix("I believe") ? belief : "I believe " + belief
                out.append(Reasons(ticker: ticker, name: name, belief: lead, reasons: pillars, dealBreakers: breaks, watch: signals,
                                   written: today, source: "framework"))
            }
        }
        return out
    }
}

/// Ask: a conversation scoped to one section. For Wealth it is how reasons get written.
public enum Ask {
    /// Everyday words for the app; the framework's terms only when Joe uses them first.
    static let language = """
    Use these everyday words. The investment framework's own terms (in brackets) stay out of your replies unless he uses them first:
    - "why you own it" or "your reasons" [thesis]; "reasons" [thesis pillars]; "deal-breakers" [break conditions]
    - "still true" [intact]; "deal-breaker hit" [break condition hit]; "not written yet" [needs a thesis]
    - "\u{201C}Still true?\u{201D} check" [quarterly thesis check]; "things to watch" [signals to monitor]; "the case against" [bear case]
    - The nine lenses are named Problem, Business model, Users, Developers, Supply chain, Smart money, Ceiling, Speed and Values [playbooks P1 to P8, plus the values filters].
    """

    public static func wealthSystem(holdings: [(name: String, ticker: String, share: Int?, written: Bool)], today: String,
                                    focus: (name: String, ticker: String)?, lens: Lens?, draft: ReasonsDraft?, existing: Reasons?) -> String {
        var s = """
        You are the voice of the Wealth section of LiveWell, Joe's private app: a calm analyst. He is an experienced technology executive who holds a few high-conviction companies for the long term in a self-managed Rollover IRA, and judges them against written reasons, not the share price. Today is \(today).

        His holdings (share of the account): \(holdings.map { "\($0.name) (\($0.ticker))\($0.share.map { " \($0)%" } ?? "")\($0.written ? "" : ", reasons not written yet")" }.joined(separator: "; ")).

        Rules:
        - Education and decision support, never buy or sell advice. Never suggest a trade, a price target or a time to act. No talk of today's price move unless he raises it.
        - Primary sources first: the annual report (10-K, or 20-F for ASML, which reports under IFRS), quarterly reports, proxy statement, investor-day material and earnings-call transcripts. Search for them, name each source with its date, and say plainly when you could not confirm something. Never invent a figure.
        - Label sentiment as sentiment and commentary as commentary. When you rely on commentary, name the author's known position if there is one. Never allege manipulation without evidence.
        - Seek the case against as hard as the case for; he has asked to be protected from confirmation bias.
        - Short replies: under 200 words unless he asks for more. Plain sentences, no headers. End with one question that moves the work forward.

        \(language)
        """
        if let focus {
            s += "\n\nYou are helping him write why he owns \(focus.name) (\(focus.ticker)). The reasons must be his. You research, ask and propose; he decides every line. Work one lens at a time."
            if let lens {
                s += "\n\nCurrent lens: \(lens.name). It asks: \(lens.asks) Look first at \(lens.sources). Bring two or three facts with their sources, ask what he makes of them, and only then propose lines."
            }
            s += """


            When you have a line worth keeping, propose it on its own line in exactly this form, at most three per reply, each one sentence in his voice:
            <propose kind="belief">I believe \(focus.name) will keep winning because …</propose>
            <propose kind="reason">…</propose>
            <propose kind="deal_breaker">…</propose>
            <propose kind="watch">…</propose>
            A reason is why it wins. A deal-breaker is a specific, observable thing that would mean a reason is no longer true. A thing to watch is a concrete signal he can check each quarter. Propose the belief line only after several lenses, when the reasons support it. The app shows each proposal with a button; a line is his only once he taps it, so never say a line has been saved.
            """
            if let draft, !draft.lines.isEmpty {
                s += "\n\nHis draft so far (already approved by him; don't re-propose these):\n" + ReasonsDraft.Kind.allCases.flatMap { kind in
                    draft.lines(kind).map { "- \(kind.heading): \($0.text)" }
                }.joined(separator: "\n")
                let left = Lens.all.filter { !draft.lensesDone.contains($0.key) }.map(\.name)
                if !left.isEmpty { s += "\nLenses not done yet: \(left.joined(separator: ", "))." }
            }
            if let existing {
                s += "\n\nHis reasons as written on \(existing.written):\n\(existing.belief)\nReasons: \(existing.reasons.joined(separator: " | "))\nDeal-breakers: \(existing.dealBreakers.joined(separator: " | "))\nThings to watch: \(existing.watch.joined(separator: " | "))"
            }
        } else {
            s += "\n\nHe may ask about any holding, about a company he is watching, or to run one lens on a company. If he wants to write or revise his reasons for a holding, tell him to open that holding on the board and start there, so the draft can build beside the conversation."
        }
        return s
    }

    public static func healthSystem(profile: String, today: String) -> String {
        """
        You are the voice of the Health section of LiveWell, Joe's private app: a warm, plain-spoken coach. Today is \(today).
        \(profile)

        Lead with how something affects his body and goals. Keep answers short (under 180 words) unless he asks for more. No markdown headers.
        Only state findings you are confident are real, name the study or organisation so he can look it up, and say plainly when evidence is mixed or only shows association. Never invent numbers. This is general education, not medical advice; suggest his doctor for anything about symptoms, medication or a condition.
        End with one short follow-up question or a concrete thing to try, when it fits.
        """
    }
}
