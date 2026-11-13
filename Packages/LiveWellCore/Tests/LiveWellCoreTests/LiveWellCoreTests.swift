import XCTest
@testable import LiveWellCore

final class LiveWellCoreTests: XCTestCase {
    let tz = TimeZone(identifier: "America/New_York")!
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c }

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: workout types (the Nov 11 miss)

    func testFunctionalStrengthCountsAsStrength() {
        let c = SurfConfig.default
        XCTAssertEqual(c.csvType(forActivity: "functionalStrengthTraining"), "strength")
        XCTAssertEqual(c.csvType(forActivity: "traditionalStrengthTraining"), "strength")
        XCTAssertEqual(c.csvType(forActivity: "yoga"), "yoga")
        XCTAssertEqual(c.csvType(forActivity: "rowing"), "rowing")
        XCTAssertEqual(c.csvType(forActivity: "walking"), "walking")
        XCTAssertEqual(c.csvType(forActivity: "hiking"), "hiking")
        XCTAssertEqual(c.csvType(forActivity: "highIntensityIntervalTraining"), "high intensity interval training")
    }

    func testTypeMapIsConfiguration() {
        var c = SurfConfig.default
        c.workoutTypeMap["pilates"] = "yoga"
        XCTAssertEqual(c.csvType(forActivity: "pilates"), "yoga")
    }

    func testConfigRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(SurfConfig.default)
        XCTAssertEqual(try JSONDecoder().decode(SurfConfig.self, from: data), .default)
    }

    // MARK: export files

    func testWorkoutsCSVMatchesSpecExample() {
        let w = ExportWriter(timeZone: tz)
        let text = w.workouts([
            WorkoutRow(start: at(2026, 11, 11, 13, 34), type: "strength", minutes: 31.6),
            WorkoutRow(start: at(2026, 10, 15, 20, 29), type: "yoga", minutes: 21.2),
        ])
        XCTAssertEqual(text, "2026-10-15 20:29,yoga,21\n2026-11-11 13:34,strength,32\n")
    }

    func testOtherFiles() {
        let w = ExportWriter(timeZone: tz)
        XCTAssertEqual(w.exerciseMinutes([DatedValue(date: at(2026, 11, 6), value: 121)]), "2026-11-06,121\n")
        XCTAssertEqual(w.vo2max([DatedValue(date: at(2026, 11, 7, 9), value: 29.26)]), "2026-11-07,29.26\n")
        XCTAssertEqual(w.weight([DatedValue(date: at(2026, 11, 12, 6), value: 172.1)]), "2026-11-12,172.1\n")
        XCTAssertEqual(w.sleep([SleepRow(start: at(2026, 11, 11, 23, 4), end: at(2026, 11, 12, 0, 10), stage: "Core")]),
                       "2026-11-11 23:04,2026-11-12 00:10,Core\n")
        XCTAssertEqual(w.workouts([]), "")
    }

    func testHeadersAreAFormatSetting() {
        var f = ExportFormats(); f.workoutsHeader = "start,type,minutes"
        let text = ExportWriter(formats: f, timeZone: tz).workouts([WorkoutRow(start: at(2026, 1, 2, 3, 4), type: "yoga", minutes: 20)])
        XCTAssertEqual(text, "start,type,minutes\n2026-01-02 03:04,yoga,20\n")
    }

    func testAtomicWriteSkipsUnchangedUnlessForced() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = dir.appendingPathComponent("health/workouts.csv")
        XCTAssertEqual(try AtomicFile.write("a\n", to: url), .written)
        XCTAssertEqual(try AtomicFile.write("a\n", to: url), .unchanged)
        XCTAssertEqual(try AtomicFile.write("a\n", to: url, always: true), .written)
        XCTAssertEqual(try AtomicFile.write("b\n", to: url), .written)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "b\n")
    }

    // MARK: checkins.csv

    func testCheckinAppendKeepsExistingLinesExactly() {
        let existing = "date,waist_in,popups_30s,sit_to_rise\n2026-11-02,40.00,9,9\n2026-11-09,39.5,10,9.5\n"
        var f = CheckinsFile(text: existing)
        f.save(date: "2026-11-16", values: ["waist_in": 39.25])
        XCTAssertEqual(f.text, existing + "2026-11-16,39.25,,\n")
    }

    func testSecondSaveSameDayReplacesAndMerges() {
        var f = CheckinsFile(text: "date,waist_in,popups_30s,sit_to_rise\n2026-11-09,39.5,10,9.5\n")
        f.save(date: "2026-11-16", values: ["waist_in": 39.5])
        f.save(date: "2026-11-16", values: ["popups_30s": 11])
        f.save(date: "2026-11-16", values: ["waist_in": 39.25, "sit_to_rise": 10])
        XCTAssertEqual(f.rows.filter { $0.date == "2026-11-16" }.count, 1)
        XCTAssertEqual(f.text, "date,waist_in,popups_30s,sit_to_rise\n2026-11-09,39.5,10,9.5\n2026-11-16,39.25,11,10\n")
    }

    func testNewFileGetsHeaderAndBlanksAreKept() {
        var f = CheckinsFile()
        f.save(date: "2026-11-16", values: ["sit_to_rise": 9.5])
        XCTAssertEqual(f.text, "date,waist_in,popups_30s,sit_to_rise\n2026-11-16,,,9.5\n")
        let back = CheckinsFile(text: f.text)
        XCTAssertNil(back.row(on: "2026-11-16")?.values["waist_in"])
        XCTAssertEqual(back.row(on: "2026-11-16")?.values["sit_to_rise"], 9.5)
    }

    func testPreviousSkipsBlanks() {
        let f = CheckinsFile(text: "2026-11-02,40,9,9\n2026-11-09,,10,\n")
        XCTAssertEqual(f.previous("waist_in", before: "2026-11-16")?.value, 40)
        XCTAssertEqual(f.previous("popups_30s", before: "2026-11-16")?.value, 10)
        XCTAssertNil(f.previous("waist_in", before: "2026-11-02"))
    }

    // MARK: habits, checked against the real dashboard of Nov 12, 2026
    // (lift 3, row 1, yoga 4, active 299 from workouts_7d and active_minutes in data.json)

    var nov12Workouts: [WorkoutRow] {
        [
            WorkoutRow(start: at(2026, 11, 5, 18, 0), type: "yoga", minutes: 20),     // outside the window
            WorkoutRow(start: at(2026, 11, 6, 14, 22), type: "yoga", minutes: 20),
            WorkoutRow(start: at(2026, 11, 6, 16, 32), type: "strength", minutes: 25),
            WorkoutRow(start: at(2026, 11, 8, 10, 31), type: "yoga", minutes: 20),
            WorkoutRow(start: at(2026, 11, 11, 13, 11), type: "yoga", minutes: 20),
            WorkoutRow(start: at(2026, 11, 11, 13, 34), type: "strength", minutes: 20),
            WorkoutRow(start: at(2026, 11, 11, 14, 46), type: "yoga", minutes: 20),
            WorkoutRow(start: at(2026, 11, 11, 20, 25), type: "rowing", minutes: 20),
            WorkoutRow(start: at(2026, 11, 11, 23, 30), type: "strength", minutes: 20),
            WorkoutRow(start: at(2026, 11, 9, 8, 0), type: "walking", minutes: 40),
        ]
    }
    var nov12Minutes: [DatedValue] {
        [(5, 60.0), (6, 121), (7, 78), (8, 28), (9, 9), (10, 9), (11, 54)].map { DatedValue(date: at(2026, 11, $0.0), value: $0.1) }
    }
    let macJSON = """
    {"date":"2026-11-12","generated":"2026-11-12T10:52","title":"Surf at 60","today":"Row today.",
     "pillars":[{"key":"strength","label":"Strength","desc":"FitClub, monthly gain","value":5.1,"display":"5.1%","from":0,"goal":3,"progress":1.0,"reached":true,"as_of":"2026-11-02","from_label":"0","goal_label":"3%"},
                {"key":"power","label":"Power","value":null,"progress":0}],
     "habits":[{"key":"lift","value":3,"goal":2,"met":true},{"key":"plan","value":4,"goal":5,"met":false}],
     "detail":{"anything":{"nested":1}}}
    """

    func testHabitCountsMatchTheMacDashboard() throws {
        let mac = try DashboardData.decode(Data(macJSON.utf8))
        let s = HabitCounter.statuses(config: .default, workouts: nov12Workouts, exerciseMinutes: nov12Minutes,
                                      mac: mac, now: at(2026, 11, 12, 10, 52), calendar: cal)
        let by = Dictionary(uniqueKeysWithValues: s.map { ($0.key, $0) })
        XCTAssertEqual(by["lift"]?.value, 3); XCTAssertEqual(by["lift"]?.met, true)
        XCTAssertEqual(by["row"]?.value, 1); XCTAssertEqual(by["row"]?.met, false)
        XCTAssertEqual(by["yoga"]?.value, 4); XCTAssertEqual(by["yoga"]?.met, true)
        XCTAssertEqual(by["active"]?.value, 299); XCTAssertEqual(by["active"]?.met, true)
        XCTAssertEqual(by["plan"]?.value, 4); XCTAssertEqual(by["plan"]?.provenance, .manual)
        XCTAssertEqual(s.map(\.key), ["lift", "row", "yoga", "active", "plan"])
    }

    func testMissingDataIsNotMeasuredNeverZero() {
        let s = HabitCounter.statuses(config: .default, workouts: [], exerciseMinutes: nil, mac: nil,
                                      now: at(2026, 11, 12, 10), calendar: cal)
        let by = Dictionary(uniqueKeysWithValues: s.map { ($0.key, $0) })
        XCTAssertNil(by["active"]?.value); XCTAssertEqual(by["active"]?.provenance, .missing)
        XCTAssertNil(by["plan"]?.value); XCTAssertEqual(by["plan"]?.met, false)
        XCTAssertEqual(by["lift"]?.value, 0)
    }

    func testFurthestBehindAndWidgetLine() throws {
        let mac = try DashboardData.decode(Data(macJSON.utf8))
        let s = HabitCounter.statuses(config: .default, workouts: nov12Workouts, exerciseMinutes: nov12Minutes,
                                      mac: mac, now: at(2026, 11, 12, 10, 52), calendar: cal)
        XCTAssertEqual(HabitCounter.furthestBehind(s)?.key, "row")   // 1/2 is less done than plan 4/5
        let fresh = WidgetSnapshot.make(config: .default, statuses: s, mac: mac, todayString: "2026-11-12", now: Date())
        XCTAssertEqual(fresh.line, "Row today")
        XCTAssertEqual(fresh.icons.map(\.met), [true, false, true, true, false])
        var stale = mac; stale.today = "Lift today."
        let old = WidgetSnapshot.make(config: .default, statuses: s, mac: stale, todayString: "2026-11-13", now: Date())
        XCTAssertEqual(old.line, "Row today")   // stale Mac advice is ignored
    }

    func testDataJSONToleratesNullsAndUnknownFields() throws {
        let mac = try DashboardData.decode(Data(macJSON.utf8))
        XCTAssertNil(mac.pillars[1].value)
        XCTAssertEqual(mac.pillars[0].goal_label, "3%")
    }

    // MARK: goal and reveal

    func testDaysLeftMatchesTheCanvas() {
        XCTAssertEqual(GoalMath.daysLeft(goal: SurfConfig.default.goal, now: at(2026, 11, 11, 6, 12), calendar: cal), 599)
        XCTAssertEqual(GoalMath.dayString(at(2026, 11, 9, 23, 59), calendar: cal), "2026-11-09")
    }

    func testRevealIsHonestBothWays() {
        let waist = SurfConfig.default.measurement("waist_in")!
        let good = Reveal.make(measurement: waist, value: 39.5, previous: ("2026-11-02", 40), baseline: ("2026-09-07", 43))
        XCTAssertEqual(good.kind, .improved)
        XCTAssertEqual(good.headline, "3.5 in down since September.")
        let same = Reveal.make(measurement: waist, value: 39.5, previous: ("2026-11-09", 39.5), baseline: nil)
        XCTAssertEqual(same.kind, .steady)
        let up = Reveal.make(measurement: waist, value: 40, previous: ("2026-11-09", 39.5), baseline: nil)
        XCTAssertEqual(up.kind, .slipped)
        XCTAssertTrue(up.headline.hasPrefix("0.5 in up from last time."))
        let pop = SurfConfig.default.measurement("popups_30s")!
        XCTAssertEqual(Reveal.make(measurement: pop, value: 11, previous: ("2026-11-09", 10), baseline: nil).headline,
                       "1 up since last time.")
        XCTAssertEqual(Reveal.make(measurement: pop, value: 10, previous: nil, baseline: nil).kind, .first)
    }
}
