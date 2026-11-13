import Foundation

// The files the Mac's build.py reads. Every formatting choice lives in ExportFormats so that
// matching the existing files byte for byte is an edit to this one struct.
//
// CONFIRMED by the build spec:  workouts.csv rows look like `2026-10-15 20:29,yoga,21`.
// ASSUMED until checked against engine/build.py and the current files on the Mac:
//   header rows, exercise_minutes.csv layout, date formats in vo2max/weight, sleep_raw.txt layout.

public struct ExportFormats: Codable, Equatable, Sendable {
    public var workoutsHeader: String? = nil
    public var workoutStart = "yyyy-MM-dd HH:mm"

    public var exerciseHeader: String? = nil
    public var exerciseDay = "yyyy-MM-dd"

    public var vo2Header: String? = nil
    public var vo2Date = "yyyy-MM-dd"
    public var vo2Decimals = 2

    public var weightHeader: String? = nil
    public var weightDate = "yyyy-MM-dd"
    public var weightDecimals = 1

    public var sleepTime = "yyyy-MM-dd HH:mm"
    public var sleepSeparator = ","

    public init() {}
}

public struct WorkoutRow: Equatable, Sendable, Codable {
    public var start: Date
    public var type: String
    public var minutes: Double
    public init(start: Date, type: String, minutes: Double) {
        self.start = start; self.type = type; self.minutes = minutes
    }
}

public struct DatedValue: Equatable, Sendable, Codable {
    public var date: Date
    public var value: Double
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}

public struct SleepRow: Equatable, Sendable {
    public var start: Date
    public var end: Date
    /// Core, Deep, REM, Asleep, Awake, In bed
    public var stage: String
    public init(start: Date, end: Date, stage: String) { self.start = start; self.end = end; self.stage = stage }
}

public struct ExportWriter: Sendable {
    public var formats: ExportFormats
    public var timeZone: TimeZone

    public init(formats: ExportFormats = ExportFormats(), timeZone: TimeZone = .current) {
        self.formats = formats; self.timeZone = timeZone
    }

    func stamp(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    static func fixed(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }

    static func assemble(header: String?, lines: [String]) -> String {
        var all = lines
        if let header { all.insert(header, at: 0) }
        return all.isEmpty ? "" : all.joined(separator: "\n") + "\n"
    }

    /// Every workout, oldest first: start (local), type, whole minutes.
    public func workouts(_ rows: [WorkoutRow]) -> String {
        let lines = rows.sorted { ($0.start, $0.type) < ($1.start, $1.type) }.map {
            "\(stamp($0.start, formats.workoutStart)),\($0.type),\(Int($0.minutes.rounded()))"
        }
        return Self.assemble(header: formats.workoutsHeader, lines: lines)
    }

    /// One row per day: day, whole Exercise minutes.
    public func exerciseMinutes(_ days: [DatedValue]) -> String {
        let lines = days.sorted { $0.date < $1.date }.map {
            "\(stamp($0.date, formats.exerciseDay)),\(Int($0.value.rounded()))"
        }
        return Self.assemble(header: formats.exerciseHeader, lines: lines)
    }

    public func vo2max(_ readings: [DatedValue]) -> String {
        let lines = readings.sorted { $0.date < $1.date }.map {
            "\(stamp($0.date, formats.vo2Date)),\(Self.fixed($0.value, formats.vo2Decimals))"
        }
        return Self.assemble(header: formats.vo2Header, lines: lines)
    }

    public func weight(_ readings: [DatedValue]) -> String {
        let lines = readings.sorted { $0.date < $1.date }.map {
            "\(stamp($0.date, formats.weightDate)),\(Self.fixed($0.value, formats.weightDecimals))"
        }
        return Self.assemble(header: formats.weightHeader, lines: lines)
    }

    public func sleep(_ rows: [SleepRow]) -> String {
        let sep = formats.sleepSeparator
        let lines = rows.sorted { ($0.start, $0.end) < ($1.start, $1.end) }.map {
            "\(stamp($0.start, formats.sleepTime))\(sep)\(stamp($0.end, formats.sleepTime))\(sep)\($0.stage)"
        }
        return Self.assemble(header: nil, lines: lines)
    }
}

/// Whole-file writes: write a temp file beside the target, then swap it in.
public enum AtomicFile {
    public enum Outcome: Equatable, Sendable { case written, unchanged }

    /// Writes `text` to `url`. Skips the write when the content is identical, unless `always` is set
    /// (build.py reads the modified time of some files to know Health has synced).
    @discardableResult
    public static func write(_ text: String, to url: URL, always: Bool = false) throws -> Outcome {
        let data = Data(text.utf8)
        if !always, let existing = try? Data(contentsOf: url), existing == data { return .unchanged }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return .written
    }
}
