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
        XCTAssertEqual(text, "start,type,minutes\n2026-10-15 20:29,yoga,21\n2026-11-11 13:34,strength,32\n")
    }

    func testOtherFiles() {
        let w = ExportWriter(timeZone: tz)
        XCTAssertEqual(w.exerciseMinutes([DatedValue(date: at(2026, 11, 6), value: 121)]), "2026-11-06,121\n")
        XCTAssertEqual(w.vo2max([DatedValue(date: at(2026, 11, 7, 9), value: 29.26)]), "2026-11-07,29.26\n")
        XCTAssertEqual(w.weight([DatedValue(date: at(2026, 11, 12, 6), value: 172.1)]), "2026-11-12,172.1\n")
        XCTAssertEqual(w.sleep([SleepRow(start: at(2026, 11, 11, 23, 4), end: at(2026, 11, 12, 0, 10), stage: "Core")]),
                       "2026-11-11 23:04:00,2026-11-12 00:10:00,Core\n")
        // Seconds are kept, as in the Shortcut's file (2026-11-04 00:34:40,2026-11-04 00:57:15,Core).
        XCTAssertEqual(w.sleep([SleepRow(start: at(2026, 11, 4, 0, 34).addingTimeInterval(40),
                                         end: at(2026, 11, 4, 0, 57).addingTimeInterval(15), stage: "Core")]),
                       "2026-11-04 00:34:40,2026-11-04 00:57:15,Core\n")
    }

    func testOnlyTheLatestReadingOfEachDayIsWritten() {
        let w = ExportWriter(timeZone: tz)
        // Nov 7: 29.26 in the morning, 28.74 in the evening. build.py would pick 29.26 from two rows.
        let vo2 = [DatedValue(date: at(2026, 11, 7, 19), value: 28.74), DatedValue(date: at(2026, 11, 7, 9), value: 29.26),
                   DatedValue(date: at(2026, 11, 6, 9), value: 29.32)]
        XCTAssertEqual(w.vo2max(vo2), "2026-11-06,29.32\n2026-11-07,28.74\n")
        let lb = [DatedValue(date: at(2026, 11, 7, 6), value: 171.07), DatedValue(date: at(2026, 11, 7, 7), value: 170.77)]
        XCTAssertEqual(w.weight(lb), "2026-11-07,170.8\n")
    }

    func testEverySessionCounts() {
        // Two yoga sessions 11 minutes apart, one of them 4 minutes long: both count.
        let rows = [WorkoutRow(start: at(2026, 11, 11, 13, 0), type: "yoga", minutes: 4),
                    WorkoutRow(start: at(2026, 11, 11, 13, 11), type: "yoga", minutes: 11)]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let s = HabitCounter.statuses(config: .default, workouts: rows, exerciseMinutes: nil, mac: nil, now: at(2026, 11, 12, 9), calendar: cal)
        XCTAssertEqual(s.first { $0.key == "yoga" }?.value, 2)
        XCTAssertTrue(SurfConfig.default.habits.allSatisfy { $0.minMinutes == 0 })
    }

    func testLiftAlsoCountsFitClubDaysAsTheMacDoes() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let rows = [WorkoutRow(start: at(2026, 11, 11, 13, 34), type: "strength", minutes: 20)]
        let fitclub: Set<String> = ["2026-11-02", "2026-11-09"]       // Nov 2 is outside the window
        let s = HabitCounter.statuses(config: .default, workouts: rows, exerciseMinutes: nil, mac: nil,
                                      sessionDays: ["fitclub": fitclub], now: at(2026, 11, 12, 9), calendar: cal)
        XCTAssertEqual(s.first { $0.key == "lift" }?.value, 2)
        XCTAssertEqual(s.first { $0.key == "row" }?.value, 0)         // only the habit that names the source
    }

    func testHeadersAreAFormatSetting() {
        var f = ExportFormats(); f.workoutsHeader = nil; f.weightHeader = "date,lb"
        let w = ExportWriter(formats: f, timeZone: tz)
        XCTAssertEqual(w.workouts([WorkoutRow(start: at(2026, 1, 2, 3, 4), type: "yoga", minutes: 20)]), "2026-01-02 03:04,yoga,20\n")
        XCTAssertEqual(w.weight([DatedValue(date: at(2026, 11, 12, 6), value: 172.1)]), "date,lb\n2026-11-12,172.1\n")
        // No rows gives no text at all, so the app never replaces a file with a lone header.
        XCTAssertEqual(ExportWriter(timeZone: tz).workouts([]), "")
    }

    // MARK: checkins.csv as the Monday Shortcut left it (one row per measurement)

    static let shortcutFile = "date,waist_in,popups_30s,sit_to_rise\n2026-11-02,39.8,,\n2026-11-02,,,9.5\n2026-11-02,,9,\n2026-11-09,39.5,,\n2026-11-09,,,9.5\n2026-11-09,,10,"

    func testSeveralRowsForADateReadAsOne() {
        let f = CheckinsFile(text: Self.shortcutFile)
        XCTAssertEqual(f.rows.count, 2)
        XCTAssertEqual(f.row(on: "2026-11-09")?.values, ["waist_in": 39.5, "sit_to_rise": 9.5, "popups_30s": 10])
        XCTAssertEqual(f.previous("popups_30s", before: "2026-11-09")?.value, 9)
    }

    func testSavingADateFoldsItsRowsAndLeavesOthersAlone() {
        var f = CheckinsFile(text: Self.shortcutFile)
        f.save(date: "2026-11-09", values: ["popups_30s": 11])
        XCTAssertEqual(f.text, "date,waist_in,popups_30s,sit_to_rise\n2026-11-02,39.8,,\n2026-11-02,,,9.5\n2026-11-02,,9,\n2026-11-09,39.5,11,9.5\n")
    }

    func testAnEarlierDateGoesInDateOrder() {
        var f = CheckinsFile(text: Self.shortcutFile)
        f.save(date: "2026-11-05", values: ["waist_in": 39.6])
        XCTAssertEqual(f.text.split(separator: "\n")[4], "2026-11-05,39.6,,")
        var g = CheckinsFile(text: "date,waist_in,popups_30s,sit_to_rise\n2026-11-09,39.5,,\n")
        g.save(date: "2026-11-02", values: ["waist_in": 40])
        XCTAssertEqual(g.text, "date,waist_in,popups_30s,sit_to_rise\n2026-11-02,40,,\n2026-11-09,39.5,,\n")
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

    // MARK: The Surf Report

    static let issueJSON = #"""
    {"date":"2026-11-12","issue":20,"intro":"Hello.","profile":"Reader: Joe.","plan_goal":5,"plan_definition":"Measured nuts.",
     "plate":{"text":"Box <b>half</b>."},"future_field":{"x":1},
     "cards":[
      {"id":"tiles","kind":"you","label":"You","pillar":"Body","tag":"Habits","win":true,
       "title":"One busy Wednesday <em>filled three tiles.</em>","why":"Row reads <span class=\"num\">1</span> &amp; counting.",
       "figure":{"type":"tiles","items":[{"v":"3/2","n":"Lift","met":true},{"v":299,"n":"Active min"}]},
       "body":["<b>A note.</b> Fewer than < 6 hours."],"try":{"label":"Try it today","text":"Walk."},
       "source":{"text":"Wastyk et al., {link}Gut study{/link}, Cell, 2021.","url":"https://example.org/a"},"starters":["Why?"]},
      {"id":"spark","kind":"science","label":"Science","title":"T",
       "figure":{"type":"spark","points":[["Jun",222],["",281.5],["Oct",554]],"marks":{"0":{"text":"222"},"2":{"text":"554","below":true}},"dashLast":true}},
      {"id":"scale","kind":"lab","label":"Lab","title":"T","figure":{"type":"scale","min":26,"max":41,"ticks":[26,33,41],"band":[33,41],"you":28.4,"goal":33}},
      {"id":"bad-figure","kind":"you","label":"You","title":"T","figure":"oops","bullets":["one"]},
      {"id":"stew","kind":"kitchen","label":"Kitchen","pillar":"Body","title":"Kimchi <em>stew</em>","why":"Feeds four.",
       "recipe":{"ingredients":["kimchi"],"steps":["simmer"],"copyText":"Kimchi stew"},"lesson":{"tag":"fibre","body":["Good."]}},
      {"id":"q","kind":"quiz","label":"Quick recall","title":"Which?","quiz":{"options":[{"t":"A"},{"t":"B","right":true}],"reveal":"B."}},
      "not a card",
      {"id":"end","kind":"end","label":"You're caught up","title":"days until <em>surf camp.</em>","why":"Tomorrow: more."}]}
    """#

    func testIssueDecodesLeniently() throws {
        let issue = try ReportIssue.decode(Data(Self.issueJSON.utf8))
        XCTAssertEqual(issue.issue, 20)
        XCTAssertEqual(issue.plate?.label, "Today's plate")
        XCTAssertEqual(issue.cards.map(\.id), ["tiles", "spark", "scale", "bad-figure", "stew", "q", "end"])
        XCTAssertEqual(issue.contentCards.count, 6)
        let tiles = try XCTUnwrap(issue.cards[0].figure)
        XCTAssertEqual(tiles.items, [.init(value: "3/2", name: "Lift", met: true), .init(value: "299", name: "Active min", met: false)])
        let spark = try XCTUnwrap(issue.cards[1].figure)
        XCTAssertEqual(spark.points.map(\.value), [222, 281.5, 554])
        XCTAssertEqual(spark.marks[2]?.below, true)
        XCTAssertTrue(spark.dashLast)
        XCTAssertEqual(issue.cards[2].figure?.band, [33, 41])
        XCTAssertNil(issue.cards[3].figure)            // a malformed figure is dropped, the card stays
        XCTAssertEqual(issue.cards[3].bullets, ["one"])
        XCTAssertEqual(issue.cards[5].quiz?.options.map(\.right), [false, true])
        XCTAssertEqual(issue.cards[0].tryIt?.text, "Walk.")
    }

    func testRichTextRunsAndPlain() {
        let runs = RichText.parse("Row reads <span class=\"num\">1</span> &amp; <em>counting</em> <b>now</b>, < 6 h. <a href=\"https://x.org/?a=1&amp;b=2\">Link</a>")
        XCTAssertEqual(runs[1], RichText.Run(text: "1", number: true))
        XCTAssertEqual(runs[2].text, " & ")
        XCTAssertTrue(runs[3].emphasis)
        XCTAssertTrue(runs[5].bold)
        XCTAssertEqual(runs.last?.link, "https://x.org/?a=1&b=2")
        XCTAssertEqual(RichText.plain("One <em>busy</em> day, < 6 h &amp; more"), "One busy day, < 6 h & more")
    }

    func testSourceLinkAndCardPlainText() throws {
        let issue = try ReportIssue.decode(Data(Self.issueJSON.utf8))
        let source = try XCTUnwrap(issue.cards[0].source)
        XCTAssertEqual(source.parts.link, "Gut study")
        XCTAssertEqual(source.plain, "Wastyk et al., Gut study, Cell, 2021.")
        let text = issue.cards[0].plainText
        XCTAssertTrue(text.hasPrefix("You · Body · Habits\n\nOne busy Wednesday filled three tiles."))
        XCTAssertTrue(text.contains("Try it today: Walk."))
        XCTAssertTrue(text.contains("A note. Fewer than < 6 hours."))
        XCTAssertFalse(text.contains("<b>") || text.contains("<span"))
    }

    func testArchiveAndRecipeBox() throws {
        let issue = try ReportIssue.decode(Data(Self.issueJSON.utf8))
        let archive = ReportArchive(issues: [issue])
        XCTAssertEqual(archive.issues.first?.count, 6)
        XCTAssertEqual(archive.issues.first?.recipes, 1)
        XCTAssertEqual(archive.issues.first?.lead, "One busy Wednesday <em>filled three tiles.</em>")
        XCTAssertEqual(archive.recipeGroups.map(\.nutrient), ["Fiber"])
        XCTAssertEqual(ReportFigure.number(1204), "1,204")
        XCTAssertEqual(ReportFigure.number(28.4), "28.4")
    }

    // MARK: plan days, feedback

    func testPlanDaysReadsTheMacFileAndWritesNotes() {
        var f = PlanDaysFile(text: "date,on,slips\n2026-10-30,0,Wine;Eating out or a party\n2026-11-11,1,\n")
        XCTAssertEqual(f["2026-10-30"]?.slips, ["Wine", "Eating out or a party"])
        f.save(PlanDay(date: "2026-11-12", on: false, slips: ["Sweets"], note: "Cake, \"just one\"", at: "2026-11-13T07:00:00Z"))
        XCTAssertEqual(f.text, "date,on,slips,note,at\n2026-10-30,0,Wine;Eating out or a party,,\n2026-11-11,1,,,\n"
                       + "2026-11-12,0,Sweets,\"Cake, \"\"just one\"\"\",2026-11-13T07:00:00Z\n")
        XCTAssertEqual(PlanDaysFile(text: f.text), f)
        // On plan clears the slips.
        XCTAssertEqual(PlanDay(date: "2026-11-12", on: true, slips: ["Wine"]).slips, [])
    }

    func testPlanCountIsTheSevenDaysEndingYesterday() {
        var f = PlanDaysFile()
        XCTAssertNil(f.count(today: "2026-11-12"))
        for (d, on) in [("2026-11-04", true), ("2026-11-05", true), ("2026-11-06", true), ("2026-11-07", true),
                        ("2026-11-08", false), ("2026-11-09", true), ("2026-11-11", true), ("2026-11-12", true)] {
            f.save(PlanDay(date: d, on: on))
        }
        XCTAssertEqual(f.lastSevenDays(before: "2026-11-12").first, "2026-11-05")
        XCTAssertEqual(f.count(today: "2026-11-12"), 5)   // Nov 4 is too old, Nov 12 is today
        XCTAssertEqual(DayMath.adding(-1, to: "2026-03-01"), "2026-02-28")
        XCTAssertEqual(DayMath.dateline("2026-11-12"), "Thu, Nov 12")
    }

    func testPlanMergeTakesTheNewerEntry() {
        var live = PlanDaysFile(text: "date,on,slips\n2026-11-10,0,\n2026-11-11,1,,,2026-11-12T09:00:00Z\n")
        var app = PlanDaysFile()
        app.save(PlanDay(date: "2026-11-10", on: true, at: "2026-11-12T08:00:00Z"))   // newer than an undated row
        app.save(PlanDay(date: "2026-11-11", on: false, at: "2026-11-12T08:00:00Z"))  // older than the live one
        live.merge(app)
        XCTAssertEqual(live["2026-11-10"]?.on, true)
        XCTAssertEqual(live["2026-11-11"]?.on, true)
    }

    func testAppPlanDaysWinOverTheMacCount() throws {
        let cal = Calendar(identifier: .gregorian)
        let mac = try DashboardData.decode(Data(#"{"pillars":[],"habits":[{"key":"plan","value":5}]}"#.utf8))
        let fromMac = HabitCounter.statuses(config: .default, workouts: [], exerciseMinutes: nil, mac: mac, now: Date(), calendar: cal)
        XCTAssertEqual(fromMac.first { $0.key == "plan" }?.value, 5)
        let fromApp = HabitCounter.statuses(config: .default, workouts: [], exerciseMinutes: nil, mac: mac, planDays: 6, now: Date(), calendar: cal)
        XCTAssertEqual(fromApp.first { $0.key == "plan" }?.value, 6)
    }

    func testVoteAndChatWindow() throws {
        let issue = try ReportIssue.decode(Data(Self.issueJSON.utf8))
        let vote = CardVote(vote: 1, issueDate: issue.date, card: issue.cards[0], at: "t")
        XCTAssertEqual(vote.title, "One busy Wednesday filled three tiles.")
        XCTAssertEqual(CardVote.key(issueDate: issue.date, cardID: "tiles"), "2026-11-12_tiles")
        XCTAssertTrue(AppFiles.json(["2026-11-12_tiles": vote]).contains("\"vote\" : 1"))
        var turns = (0..<15).map { GoDeeper.Turn(fromReader: $0 % 2 == 0, text: "\($0)") }
        XCTAssertEqual(GoDeeper.window(turns).first?.text, "4")   // 12 would start on an answer; drop it
        turns.removeLast()
        XCTAssertEqual(GoDeeper.window(turns).count, 12)
        XCTAssertTrue(GoDeeper.system(profile: "Reader: Joe.", cardText: "CARD").contains("\"\"\"\nCARD\n\"\"\""))
    }

    // MARK: sections

    func testOldConfigFileBecomesTheHealthSection() throws {
        // config.json as Phase 1 and 2 saved it: goal, habits and measurements at the top level.
        struct Old: Encodable { var goal: GoalDefinition; var habits: [HabitDefinition]; var measurements: [MeasurementDefinition]
                                var workoutTypeMap: [String: String]; var habitWindowDays: Int }
        var habits = SurfConfig.default.habits
        habits[0].goal = 3; habits[0].symbol = nil
        let old = Old(goal: SurfConfig.default.goal, habits: habits, measurements: SurfConfig.default.measurements,
                      workoutTypeMap: ["pilates": "yoga"], habitWindowDays: 7)
        let config = try JSONDecoder().decode(SurfConfig.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(config.sections.map(\.key), ["health"])
        XCTAssertEqual(config.habit("lift")?.goal, 3)                       // his edits survive
        XCTAssertEqual(config.habit("lift")?.symbolName, "dumbbell.fill")   // and old habits still get their icon
        XCTAssertEqual(config.workoutTypeMap, ["pilates": "yoga"])
        XCTAssertEqual(config.goal.title, "Surf at 60")
        XCTAssertTrue(config.planHistory.isEmpty)
    }

    func testASectionNeedsNothingButAName() throws {
        var config = SurfConfig.default
        config.sections.append(try JSONDecoder().decode(SectionDefinition.self, from: Data(#"{"key":"money"}"#.utf8)))
        XCTAssertEqual(config.sectionName("money"), "Money")
        XCTAssertEqual(config.sectionName("family"), "Family")        // unknown sections still read well
        XCTAssertEqual(config.section("money")?.habits.count, 0)
        XCTAssertEqual(config.habits.count, 5)                         // Today still shows the dashboard section
        config.habits[0].goal = 4
        XCTAssertEqual(config.sections[0].habits[0].goal, 4)
        let back = try JSONDecoder().decode(SurfConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(back, config)
    }

    func testIssuesAndCardsCarryASection() throws {
        let health = try ReportIssue.decode(Data(Self.issueJSON.utf8))
        XCTAssertEqual(health.section, "health")                       // existing issues default to Health
        XCTAssertEqual(health.sections, ["health"])
        let mixed = try ReportIssue.decode(Data(#"""
        {"date":"2026-12-01","cards":[{"id":"a","kind":"you","label":"You","title":"A"},
          {"id":"b","kind":"science","label":"Money","title":"B","section":"Money"},{"id":"end","kind":"end","label":"x","title":"y","section":"family"}]}
        """#.utf8))
        XCTAssertEqual(mixed.sections, ["health", "money"])            // the end card doesn't add a section
        XCTAssertEqual(mixed.section(of: mixed.cards[1]), "money")
        XCTAssertEqual(ReportArchive(issues: [health, mixed]).sections, ["health", "money"])
        let vote = CardVote(vote: 1, issueDate: mixed.date, card: mixed.cards[1], section: "money", at: "t")
        XCTAssertTrue(AppFiles.json(vote).contains("\"section\" : \"money\""))
        // Votes saved before sections existed still load.
        let old = try JSONDecoder().decode(CardVote.self, from: Data(#"{"vote":1,"date":"d","card":"c","kind":"you","pillar":"","label":"","title":"","at":"t"}"#.utf8))
        XCTAssertNil(old.section)
        XCTAssertTrue(GoDeeper.system(profile: "", cardText: "", section: "Money").contains("personal money feed"))
    }

    func testWidgetSnapshotCarriesCountsBarsAndDays() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let mac = try DashboardData.decode(Data(#"{"date":"2026-11-12","today":"Row today.","pillars":[{"key":"cardio","label":"Cardio","progress":0.47,"reached":false},{"key":"power","label":"Power"}],"habits":[]}"#.utf8))
        let rows = [WorkoutRow(start: at(2026, 11, 11, 13), type: "yoga", minutes: 11)]
        let now = at(2026, 11, 12, 9)
        let statuses = HabitCounter.statuses(config: .default, workouts: rows, exerciseMinutes: [DatedValue(date: at(2026, 11, 11), value: 265)],
                                             mac: mac, planDays: 5, now: now, calendar: cal)
        let snap = WidgetSnapshot.make(config: .default, statuses: statuses, mac: mac, todayString: "2026-11-12", now: now, calendar: cal)
        XCTAssertEqual(snap.icons.map(\.count), ["0/2", "0/2", "1/3", "265", "5/5"])
        XCTAssertEqual(snap.icons.map(\.symbol), ["dumbbell.fill", "figure.rower", "figure.yoga", "figure.walk", "fork.knife"])
        XCTAssertEqual(snap.bars?.map(\.key), ["cardio"])              // a pillar with no reading has no bar
        XCTAssertEqual(snap.daysLeft, 598)
        XCTAssertEqual(snap.activeMinutes, 265)
        var later = snap; later.updated = Date()
        XCTAssertTrue(snap.sameContent(as: later))
        // A snapshot written by the Phase 1 build still decodes.
        let old = #"{"line":"Row today","icons":[{"key":"lift","name":"Lift","met":true}],"activeGoal":250,"updated":"2026-11-12T10:00:00Z"}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertNil(try decoder.decode(WidgetSnapshot.self, from: Data(old.utf8)).bars)
    }

    // MARK: plan review

    func testReviewProposesAtMostOneChange() {
        typealias H = PlanReview.HabitWeeks
        typealias P = PlanReview.PillarTrend
        let row = H(key: "row", name: "Row", goal: 2, weeks: [2, 3], pillars: ["cardio"])
        let yoga = H(key: "yoga", name: "Yoga", goal: 3, weeks: [1, 2], pillars: ["mobility"])
        let flatCardio = P(key: "cardio", label: "Cardio", trend: .flat, from: 29.3, to: 29.3, goal: 33)
        // Met both weeks, pillar flat: step up (and only that, though Yoga was also missed twice).
        let up = PlanReview.propose(habits: [row, yoga], pillars: [flatCardio])
        XCTAssertEqual([up.kind, up.key], ["habit", "row"])
        XCTAssertEqual(up.to, 3)
        XCTAssertTrue(up.reason.contains("29.3"))
        // Met both weeks and the pillar is moving: leave it; the missed habit gets a smaller target.
        let movingCardio = P(key: "cardio", label: "Cardio", trend: .up, from: 28.8, to: 29.3, goal: 33)
        let down = PlanReview.propose(habits: [row, yoga], pillars: [movingCardio])
        XCTAssertEqual([down.key, "\(down.to)"], ["yoga", "2.0"])
        // A reached pillar with a next goal.
        let power = P(key: "power", label: "Power", trend: .up, from: 7, to: 10, goal: 10, nextGoal: 15, reached: true)
        let next = PlanReview.propose(habits: [row], pillars: [movingCardio, power])
        XCTAssertEqual([next.kind, next.key], ["pillar", "power"])
        XCTAssertEqual(next.headline, "Power reached 10. Make 15 the goal?")
        // Nothing to change. One met week and one missed week is not a pattern.
        let mixed = H(key: "lift", name: "Lift", goal: 2, weeks: [1, 2], pillars: ["strength"])
        let stay = PlanReview.propose(habits: [mixed], pillars: [movingCardio])
        XCTAssertFalse(stay.isChange)
        XCTAssertEqual(stay.reason, "Cardio is moving. The plan is working; keep it.")
        // A week that wasn't measured is never treated as a miss.
        let unmeasured = H(key: "active", name: "Active", goal: 250, weeks: [nil, 120], pillars: ["body"])
        XCTAssertFalse(PlanReview.propose(habits: [unmeasured], pillars: []).isChange)
        XCTAssertEqual(PlanReview.stepUp(250), 275)
        XCTAssertEqual(PlanReview.stepDown(250), 200)
        XCTAssertEqual(PlanReview.stepDown(1), 1)
    }

    func testFourWeekTrendAndCadence() {
        let waist = [("2026-10-06", 41.0), ("2026-10-26", 40.0), ("2026-11-09", 39.5)]
        let t = PlanReview.trend(history: waist, today: "2026-11-13", lowerIsBetter: true, span: 3)
        XCTAssertEqual(t.trend, .up)                 // lower is better, and it fell
        XCTAssertEqual(t.from, 41.0)
        let flat = PlanReview.trend(history: [("2026-10-10", 29.3), ("2026-11-07", 29.32)], today: "2026-11-13", lowerIsBetter: false, span: 7)
        XCTAssertEqual(flat.trend, .flat)
        // Under two weeks of history says nothing.
        XCTAssertEqual(PlanReview.trend(history: [("2026-11-09", 3.0), ("2026-11-12", 5.0)], today: "2026-11-13", lowerIsBetter: false, span: 3).trend, .unknown)
        XCTAssertTrue(PlanReview.isDue(lastReview: nil, today: "2026-11-16"))
        XCTAssertFalse(PlanReview.isDue(lastReview: "2026-11-09", today: "2026-11-16"))
        XCTAssertTrue(PlanReview.isDue(lastReview: "2026-11-02", today: "2026-11-16"))
    }

    func testGoalIsWrittenIntoSettingsJSONWithoutDisturbingIt() {
        let text = """
        {
          "title": "Surf at 60",
          "pillars": {
            "power": { "label": "Power {x}", "from": 0, "goal": 10, "next_goal": 15, "source": "checkins.csv \\"popups\\", goal" },
            "body": {"goal": 40}
          },
          "habits_last_7_days": {
            "row": {
              "goal": 2,
              "counts": "Apple rowing workouts"
            },
            "active": { "goal": 250 }
          }
        }
        """
        let edited = JSONText.setting(3, at: ["habits_last_7_days", "row", "goal"], in: text)
        XCTAssertEqual(edited, text.replacingOccurrences(of: "\"goal\": 2,", with: "\"goal\": 3,"))
        XCTAssertEqual(JSONText.number(at: ["pillars", "power", "next_goal"], in: text), 15)
        XCTAssertEqual(JSONText.number(at: ["pillars", "body", "goal"], in: text), 40)
        let power = JSONText.setting(15, at: ["pillars", "power", "goal"], in: text)
        XCTAssertEqual(power, text.replacingOccurrences(of: "\"goal\": 10,", with: "\"goal\": 15,"))
        XCTAssertNil(JSONText.setting(1, at: ["habits_last_7_days", "swim", "goal"], in: text))
    }
}
