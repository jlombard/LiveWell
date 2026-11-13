import Foundation

/// checkins.csv: `date,waist_in,popups_30s,sit_to_rise`, blank fields allowed, never two rows for a date.
/// Existing lines are kept exactly as they are; only the row for the saved date is added or rewritten.
public struct CheckinsFile: Equatable, Sendable {
    public static let columns = ["waist_in", "popups_30s", "sit_to_rise"]
    public static let header = "date," + columns.joined(separator: ",")

    public struct Row: Equatable, Sendable {
        public var date: String                 // yyyy-MM-dd
        public var values: [String: Double]     // by column name; missing = blank
        public init(date: String, values: [String: Double]) { self.date = date; self.values = values }
    }

    enum Line: Equatable, Sendable {
        case row(Row, original: String?)   // original text is reused unless the row was edited
        case other(String)                 // header, comments, anything unrecognised
    }

    var lines: [Line] = []

    public init() {}

    public init(text: String) {
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = parts.first, Self.isDate(first) {
                var values: [String: Double] = [:]
                for (i, column) in Self.columns.enumerated() where i + 1 < parts.count {
                    if let v = Double(parts[i + 1]) { values[column] = v }
                }
                lines.append(.row(Row(date: first, values: values), original: line))
            } else {
                lines.append(.other(line))
            }
        }
    }

    static func isDate(_ s: String) -> Bool {
        let p = s.split(separator: "-")
        return s.count == 10 && p.count == 3 && p.allSatisfy { Int($0) != nil }
    }

    public var rows: [Row] {
        lines.compactMap { if case .row(let r, _) = $0 { return r } else { return nil } }
            .sorted { $0.date < $1.date }
    }

    public func row(on date: String) -> Row? { rows.first { $0.date == date } }

    /// Adds values to the row for `date`, creating it if needed. A second save that day replaces
    /// the same row; fields not passed keep what they had.
    public mutating func save(date: String, values: [String: Double]) {
        if let i = lines.firstIndex(where: { if case .row(let r, _) = $0 { return r.date == date } else { return false } }),
           case .row(var row, _) = lines[i] {
            row.values.merge(values) { _, new in new }
            lines[i] = .row(row, original: nil)
        } else {
            if lines.isEmpty { lines.append(.other(Self.header)) }
            lines.append(.row(Row(date: date, values: values), original: nil))
        }
    }

    public var text: String {
        lines.map { line -> String in
            switch line {
            case .other(let s): return s
            case .row(_, let original?): return original
            case .row(let row, nil):
                return ([row.date] + Self.columns.map { row.values[$0].map(Self.number) ?? "" }).joined(separator: ",")
            }
        }.joined(separator: "\n") + "\n"
    }

    /// 39.5, 39.25, 10 (no trailing zeros).
    public static func number(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// Readings for one column, oldest first.
    public func history(_ column: String) -> [(date: String, value: Double)] {
        rows.compactMap { r in r.values[column].map { (r.date, $0) } }
    }

    /// The latest reading strictly before `date`.
    public func previous(_ column: String, before date: String) -> (date: String, value: Double)? {
        history(column).last { $0.date < date }
    }
}
