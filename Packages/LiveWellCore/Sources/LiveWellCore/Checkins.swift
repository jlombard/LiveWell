import Foundation

/// checkins.csv: `date,waist_in,popups_30s,sit_to_rise`, blank fields allowed.
/// The Monday Shortcut wrote one row per measurement, so a date can have several rows; they are
/// read as one (build.py takes the last row in file order that has a value, and so does this).
/// Lines for other dates are kept exactly as they are; saving a date folds its rows into one.
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

    /// One row per date (several lines for a date are merged, later lines winning), oldest first.
    public var rows: [Row] {
        var byDate: [String: Row] = [:]
        for case .row(let r, _) in lines {
            byDate[r.date, default: Row(date: r.date, values: [:])].values.merge(r.values) { _, new in new }
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    public func row(on date: String) -> Row? { rows.first { $0.date == date } }

    private func date(at index: Int) -> String? {
        if case .row(let r, _) = lines[index] { return r.date } else { return nil }
    }

    /// Adds values to the row for `date`, creating it if needed. A second save that day replaces
    /// the same row; fields not passed keep what they had. A new date goes in date order, because
    /// build.py reads "latest" as the last line in the file.
    public mutating func save(date: String, values: [String: Double]) {
        let matches = lines.indices.filter { self.date(at: $0) == date }
        if let first = matches.first {
            var row = Row(date: date, values: [:])
            for i in matches {
                if case .row(let r, _) = lines[i] { row.values.merge(r.values) { _, new in new } }
            }
            row.values.merge(values) { _, new in new }
            lines[first] = .row(row, original: nil)
            for i in matches.dropFirst().reversed() { lines.remove(at: i) }
        } else {
            if lines.isEmpty { lines.append(.other(Self.header)) }
            let after = lines.indices.last { i in self.date(at: i).map { $0 <= date } ?? false }
            let index = after.map { $0 + 1 } ?? lines.indices.first { self.date(at: $0) != nil } ?? lines.count
            lines.insert(.row(Row(date: date, values: values), original: nil), at: index)
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
