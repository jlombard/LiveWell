import Foundation

// The food check-in ("plan days"), reader feedback and kept answers. The app owns these files;
// the Mac's morning run reads them (engine/surf_report_guide.md, "App files").

public struct PlanDay: Codable, Equatable, Sendable {
    public var date: String          // yyyy-MM-dd
    public var on: Bool
    public var slips: [String]
    public var note: String
    /// ISO 8601 time of the last change; the newer entry wins when two sources have the same day.
    public var at: String

    public init(date: String, on: Bool, slips: [String] = [], note: String = "", at: String = "") {
        self.date = date; self.on = on; self.slips = on ? [] : slips; self.note = note; self.at = at
    }
}

/// plan_days.csv: `date,on,slips,note,at`. build.py reads the first three columns (on = 1/0,
/// slips joined with `;`); the note and the time are for the morning run and the app.
public struct PlanDaysFile: Equatable, Sendable {
    public static let header = "date,on,slips,note,at"
    public static let slipChoices = ["Nuts or snacks", "Office lunch", "Dinner portions", "Wine", "Sweets",
                                     "Eating out or a party"]

    public private(set) var days: [String: PlanDay] = [:]

    public init() {}

    public init(text: String) {
        for cells in CSV.parse(text) {
            guard let date = cells.first, CheckinsFile.isDate(date), cells.count > 1,
                  cells[1] == "0" || cells[1] == "1" else { continue }
            let slips = cells.count > 2 ? cells[2].split(separator: ";").map {
                $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : []
            days[date] = PlanDay(date: date, on: cells[1] == "1", slips: slips,
                                 note: cells.count > 3 ? cells[3] : "", at: cells.count > 4 ? cells[4] : "")
        }
    }

    public var sorted: [PlanDay] { days.values.sorted { $0.date < $1.date } }
    public subscript(date: String) -> PlanDay? { days[date] }
    public var isEmpty: Bool { days.isEmpty }

    public mutating func save(_ day: PlanDay) { days[day.date] = day }

    /// Takes the other file's days when they are new here or changed more recently.
    public mutating func merge(_ other: PlanDaysFile) {
        for (date, theirs) in other.days {
            if let mine = days[date], mine.at >= theirs.at, !(mine.at.isEmpty && !theirs.at.isEmpty) { continue }
            days[date] = theirs
        }
    }

    public var text: String {
        let lines = sorted.map { d in
            [d.date, d.on ? "1" : "0", d.slips.joined(separator: ";"), d.note, d.at].map(CSV.field).joined(separator: ",")
        }
        return ([Self.header] + lines).joined(separator: "\n") + "\n"
    }

    /// On-plan days over the 7 days ending yesterday, as build.py counts them. Nil when nothing
    /// has ever been logged ("not measured", never zero).
    public func count(today: String) -> Int? {
        if days.isEmpty { return nil }
        return lastSevenDays(before: today).filter { days[$0]?.on == true }.count
    }

    /// The 7 dates ending yesterday, oldest first.
    public func lastSevenDays(before today: String) -> [String] {
        (1...7).reversed().compactMap { DayMath.adding(-$0, to: today) }
    }

    /// What the Go deeper chat is told about the food plan (the last 14 logged days).
    public func summary(definition: String, goal: Int, today: String, plate: String?) -> String {
        let recent = sorted.suffix(14)
        if recent.isEmpty { return "No days logged yet." }
        let lines = recent.map { d -> String in
            var line = d.date + ": " + (d.on ? "on plan" : "off plan")
            if !d.slips.isEmpty { line += " (got in the way: " + d.slips.joined(separator: ", ") + ")" }
            if !d.note.isEmpty { line += " - note: \"\(d.note)\"" }
            return line
        }
        var out = "His plan: \(definition) Goal: \(goal) on-plan days a week. Today is \(today). "
            + "His logged days (most recent last):\n" + lines.joined(separator: "\n")
        if let plate, !plate.isEmpty { out += "\nToday's plate tip: " + RichText.plain(plate) }
        return out
    }
}

/// Date arithmetic on yyyy-MM-dd strings, independent of time zone.
public enum DayMath {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    public static func date(_ day: String) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    public static func string(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func adding(_ days: Int, to day: String) -> String? {
        guard let d = date(day), let moved = calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return string(moved)
    }

    /// 1 = Sunday … 7 = Saturday.
    public static func weekday(_ day: String) -> Int? { date(day).map { calendar.component(.weekday, from: $0) } }

    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public static func weekdayName(_ day: String) -> String { weekday(day).map { weekdays[$0 - 1] } ?? day }

    /// "Thu, Nov 12"
    public static func dateline(_ day: String) -> String {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return day }
        return "\(weekdayName(day).prefix(3)), \(months[p[1] - 1]) \(p[2])"
    }
}

/// Minimal RFC 4180 reading and writing (quoted fields, doubled quotes, newlines inside quotes).
public enum CSV {
    public static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, started = false
        var i = text.startIndex
        func endRow() {
            row.append(cell); cell = ""
            if started { rows.append(row) }
            row = []; started = false
        }
        while i < text.endIndex {
            let ch = text[i]
            if quoted {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" { cell.append("\""); i = next } else { quoted = false }
                } else { cell.append(ch) }
            } else if ch == "\"" && cell.isEmpty { quoted = true; started = true }
            else if ch == "," { row.append(cell); cell = ""; started = true }
            else if ch.isNewline { endRow() }
            else { cell.append(ch); started = true }
            i = text.index(after: i)
        }
        if started || !cell.isEmpty { started = true; endRow() }
        return rows
    }
}

/// A thumbs up or down on one card. File: app/feedback.json, keyed "<issue date>_<card id>".
public struct CardVote: Codable, Equatable, Sendable {
    public var vote: Int            // 1, -1, or 0 (cleared)
    public var date: String
    public var card: String
    public var kind: String
    public var pillar: String
    public var label: String
    public var title: String
    public var at: String

    public init(vote: Int, issueDate: String, card: ReportCard, at: String) {
        self.vote = vote; date = issueDate; self.card = card.id; kind = card.kind
        pillar = card.pillar ?? ""; label = card.label; title = RichText.plain(card.title); self.at = at
    }

    public static func key(issueDate: String, cardID: String) -> String { issueDate + "_" + cardID }
}

/// A chat answer worth keeping. File: app/saved.json (a list, oldest first).
public struct SavedAnswer: Codable, Equatable, Identifiable, Sendable {
    public var question: String
    public var answer: String
    public var date: String
    public var card: String
    public var pillar: String
    public var cardTitle: String
    public var at: String

    public var id: String { at + question }

    public init(question: String, answer: String, date: String, card: String, pillar: String, cardTitle: String, at: String) {
        self.question = question; self.answer = answer; self.date = date; self.card = card
        self.pillar = pillar; self.cardTitle = cardTitle; self.at = at
    }
}

/// Tells the morning run who owns what. File: app/status.json.
public struct AppStatusFile: Codable, Equatable, Sendable {
    /// true: the app writes health_app/ and the Shortcuts and the web page are still live.
    /// false: the app owns health/ (including plan_days.csv) and checkins.csv.
    public var trial_mode: Bool
    public var plan_days: String
    public var feedback: String
    public var saved: String
    public var updated: String

    public init(trialMode: Bool, planDays: String, updated: String) {
        trial_mode = trialMode; plan_days = planDays; feedback = AppFiles.feedback; saved = AppFiles.saved
        self.updated = updated
    }
}

public enum AppFiles {
    public static let feedback = "app/feedback.json"
    public static let saved = "app/saved.json"
    public static let status = "app/status.json"

    public static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }.map { $0 + "\n" } ?? ""
    }
}

/// The Go deeper chat: what Claude is told, mirroring the web report.
public enum GoDeeper {
    public struct Turn: Equatable, Sendable {
        public var fromReader: Bool
        public var text: String
        public init(fromReader: Bool, text: String) { self.fromReader = fromReader; self.text = text }
    }

    public static let planStarters = ["What keeps tripping me up, and one fix?", "Ideas for an on-plan weekend",
                                      "How does the food plan move my waist?"]

    public static func system(profile: String, cardText: String) -> String {
        """
        You are the voice of "The Surf Report", Joe's personal health feed. He tapped "Go deeper" on one card and wants to learn more.
        \(profile)

        Style: warm, plain-spoken, like a knowledgeable coach. Lead with how it affects his body and goals, not with what he did. Keep answers short (under 180 words) unless he asks for more. No markdown headers; short paragraphs or a few dashes are fine.
        Science: only state findings you are confident are real, name the study or organisation (author, journal, year) so he can look it up, and say plainly when evidence is mixed or only shows association. Never invent numbers. This is general education, not medical advice; suggest his doctor for anything about symptoms, medication or a condition.
        End with one short follow-up question or a concrete thing to try, when it fits.

        The card he is reading:
        \"\"\"
        \(cardText)
        \"\"\"
        """
    }

    /// The last 12 turns, starting with one from the reader (the API needs that).
    public static func window(_ turns: [Turn]) -> [Turn] {
        var recent = Array(turns.suffix(12))
        while let first = recent.first, !first.fromReader { recent.removeFirst() }
        return recent
    }
}
