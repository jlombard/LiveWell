import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit
import LiveWellCore

enum AppTab: Hashable { case today, sections, rituals }

/// A screen pushed inside a tab.
enum Route: Hashable {
    /// A section's home: its dashboard, today's issue, its library and its rituals.
    case section(String)
    /// A section's edition (the reader).
    case issue(String)
    case checkin
    case library
    /// One holding: its reasons, or the way to write them.
    case holding(String)
    /// Ask, scoped to a section and optionally to one holding.
    case ask(String, String?)
    /// Wealth's ceremonies for one holding.
    case watch(String)
    case stillTrue(String)
    case values(String)
}

struct FileStatus: Codable, Equatable {
    var lastWrite: Date?
    var lastChecked: Date?
    var lastError: String?
}

struct AppSettings: Codable, Equatable {
    /// Trial mode writes into health_app/ beside the Shortcuts' files so the two can be compared.
    /// Turn it off at cutover and the app writes the live files.
    var trialMode = true
    var reminderOn = true
    var reminderHour = 7
    var reminderMinute = 0
    var exerciseDays = 35
    var sleepDays = 14
    var formats = ExportFormats()
    /// The Claude model the Go deeper chat uses.
    var chatModel = ClaudeClient.defaultModel
    /// Tell me when a new Surf Report issue arrives.
    var issueAlerts = true
    /// The Wealth widget and front-page number: the day's change in place of the week's.
    var wealthDaily = false

    init() {}

    /// A settings file saved by an older build is missing newer keys; they take their defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        trialMode = try c.decodeIfPresent(Bool.self, forKey: .trialMode) ?? d.trialMode
        reminderOn = try c.decodeIfPresent(Bool.self, forKey: .reminderOn) ?? d.reminderOn
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute
        exerciseDays = try c.decodeIfPresent(Int.self, forKey: .exerciseDays) ?? d.exerciseDays
        sleepDays = try c.decodeIfPresent(Int.self, forKey: .sleepDays) ?? d.sleepDays
        formats = (try? c.decodeIfPresent(ExportFormats.self, forKey: .formats)) ?? d.formats
        chatModel = try c.decodeIfPresent(String.self, forKey: .chatModel) ?? d.chatModel
        issueAlerts = try c.decodeIfPresent(Bool.self, forKey: .issueAlerts) ?? d.issueAlerts
        wealthDaily = try c.decodeIfPresent(Bool.self, forKey: .wealthDaily) ?? d.wealthDaily
    }

    var healthFolder: String { trialMode ? "health_app" : "health" }
    var checkinsPath: String { trialMode ? "health_app/checkins.csv" : "checkins.csv" }
}

struct LoggedNote: Equatable {
    var pillar: String
    var text: String
}

/// The app's single source of truth: configuration, the Mac's data.json, habit counts computed
/// on the phone, the check-in file, and the sync pipeline that ties them together.
@MainActor
@Observable
final class AppModel {
    static let refreshTaskID = "livewell.refresh"

    let container: ModelContainer
    let health = HealthSync()
    let folder = HealthGlanceFolder()
    let report: ReportStore
    let wealth = WealthStore()
    let ask = AskStore()

    var config: SurfConfig { didSet { if config != oldValue { persist(config, "config.json"); recompute() } } }
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persist(settings, "settings.json")
            scheduleReminder()
            if settings.trialMode != oldValue.trialMode {
                if !settings.trialMode { finishCutover() }
                Task { await report.reload(); await sync() }
            }
        }
    }

    private(set) var dashboard: DashboardData?
    /// Pillar values over time, by pillar key then day, recorded from data.json as it arrives.
    /// The plan review reads 4-week trends from it.
    var pillarHistory: [String: [String: Double]] = [:]
    /// Days with a session from a source other than Health, by source name ("fitclub": ARX main sets).
    private(set) var sessionDays: [String: Set<String>] = [:]
    /// Committed weeks with their per-habit targets, oldest first.
    private(set) var commitments: [WeekRecord] = []
    /// Every "Name the company" puzzle played, by issue date. Kept on the phone.
    var puzzles = PuzzleStats() { didSet { if puzzles != oldValue { persist(puzzles, "puzzles.json") } } }
    /// What happened at cutover (shown in Settings).
    var cutoverNote: String?
    private(set) var statuses: [HabitStatus] = []
    private(set) var checkins = CheckinsFile()
    private(set) var fileStatus: [String: FileStatus] = [:]
    private(set) var lastSync: Date?
    private(set) var syncError: String?
    private(set) var isSyncing = false
    private(set) var healthLocked = false
    private(set) var folderLinked = false

    var tab: AppTab = .today
    /// What is pushed in each tab.
    var paths: [AppTab: [Route]] = [:]
    /// The newest issue date read, by section, for the unread dot on the front page.
    var readIssues: [String: String] = UserDefaults.standard.dictionary(forKey: "readIssues") as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(readIssues, forKey: "readIssues") }
    }
    var lastLogged: LoggedNote?

    private var exerciseMinutes: [DatedValue]?
    /// Per-day Exercise minutes (35 days), for the plan review's two weeks.
    var exerciseMinutesForReview: [DatedValue]? { exerciseMinutes }
    private var syncAgain = false

    var context: ModelContext { container.mainContext }
    var calendar: Calendar { Calendar.current }

    init() {
        container = try! ModelContainer(for: WorkoutEntry.self, HealthReading.self, MeasurementEntry.self,
                                        Reflection.self, WeekCommitment.self, CommitmentRecord.self)
        report = ReportStore(folder: folder)
        config = Self.load("config.json") ?? .default
        settings = Self.load("settings.json") ?? AppSettings()
        fileStatus = Self.load("filestatus.json") ?? [:]
        exerciseMinutes = Self.load("exercise.json")
        pillarHistory = Self.load("pillars.json") ?? [:]
        puzzles = Self.load("puzzles.json") ?? PuzzleStats()
        #if DEBUG && targetEnvironment(simulator)
        // Simulator only: `-demoGuesses "Walmart,Costco" -demoPuzzle 2026-11-13` shows a game in progress.
        if let list = UserDefaults.standard.string(forKey: "demoGuesses"), let id = UserDefaults.standard.string(forKey: "demoPuzzle") {
            var game = PuzzleGame(answer: UserDefaults.standard.string(forKey: "demoAnswer") ?? "Costco")
            for name in list.split(separator: ",") { _ = game.guess(String(name)) }
            puzzles.games = [id: game]
        }
        #endif
        let saved = (try? container.mainContext.fetch(FetchDescriptor<CommitmentRecord>(sortBy: [SortDescriptor(\.savedAt)]))) ?? []
        commitments = saved.compactMap { try? JSONDecoder().decode(WeekRecord.self, from: $0.record) }
        #if DEBUG && targetEnvironment(simulator)
        // Simulator only: `-demoFolder <path>` links a folder on the Mac without the file picker.
        if let path = UserDefaults.standard.string(forKey: "demoFolder") { try? folder.link(URL(fileURLWithPath: path)) }
        switch UserDefaults.standard.string(forKey: "demoTab") {
        case "report": paths[.today] = [.issue(SectionDefinition.healthKey)]
        case "health": paths[.today] = [.section(SectionDefinition.healthKey)]
        case "wealth": paths[.today] = [.section(Wealth.sectionKey)]
        case "wealthissue": paths[.today] = [.issue(Wealth.sectionKey)]
        case "holding": paths[.today] = [.section(Wealth.sectionKey), .holding(UserDefaults.standard.string(forKey: "demoTicker") ?? "ASML")]
        case "watch": paths[.today] = [.watch(UserDefaults.standard.string(forKey: "demoTicker") ?? "NVDA")]
        case "stilltrue": paths[.today] = [.stillTrue(UserDefaults.standard.string(forKey: "demoTicker") ?? "ASML")]
        case "values": paths[.today] = [.values(UserDefaults.standard.string(forKey: "demoTicker") ?? "AAPL")]
        case "ask": paths[.today] = [.section(Wealth.sectionKey), .ask(Wealth.sectionKey, UserDefaults.standard.string(forKey: "demoTicker"))]
        case "sections": tab = .sections
        case "rituals": tab = .rituals
        case "library": tab = .sections; paths[.sections] = [.library]
        default: break
        }
        #endif
        folderLinked = folder.isLinked
        folder.onDashboardChange = { [weak self] in self?.loadDashboard() }
        folder.onReportChange = { [weak self] in Task { await self?.report.reload() } }
        report.trialMode = { [weak self] in self?.settings.trialMode ?? true }
        report.onPlanChange = { [weak self] in self?.recompute() }
        report.onNewIssue = { [weak self] issue, section in self?.announce(issue, section: section) }
        report.otherFolders = { [weak self] in
            guard let self else { return [:] }
            let main = self.config.dashboardSection?.key
            return Dictionary(uniqueKeysWithValues: self.config.sections.filter { $0.key != main && $0.editionName != nil }.map { ($0.key, $0.issuesFolder) })
        }
        wealth.onChange = { [weak self] in self?.wealthChanged() }
        if !wealth.holdings.isEmpty, config.section(Wealth.sectionKey) == nil { wealthChanged() }
        loadFramework()
        Task { await report.reload() }
        loadDashboard()
        loadCheckins()
        recompute()
    }

    // MARK: lifecycle

    /// Called at every launch, foreground or background.
    func start() {
        health.startObserving { [weak self] in await self?.sync() }
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.healthLocked else { return }
                await self.sync()
            }
        }
        scheduleReminder()
    }

    func connectHealth() async {
        do {
            try await health.requestAccess()
            health.startObserving { [weak self] in await self?.sync() }
            await sync()
        } catch {
            syncError = error.localizedDescription
        }
    }

    func linkFolder(_ url: URL) {
        do {
            try folder.link(url)
            folderLinked = folder.isLinked
            loadDashboard()
            loadCheckins()
            Task { await report.reload(); await sync() }
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: the sync pipeline: Health -> store -> CSV files -> data.json -> widget

    func sync() async {
        if isSyncing { syncAgain = true; return }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            await syncOnce()
        } while syncAgain
    }

    private func syncOnce() async {
        var sleep: [SleepRow]?
        if health.hasRequested {
            do {
                let pull = try await health.pull(into: context, exerciseDays: settings.exerciseDays, sleepDays: settings.sleepDays)
                exerciseMinutes = pull.exerciseMinutes
                persist(exerciseMinutes, "exercise.json")
                sleep = pull.sleep
                healthLocked = false
                syncError = nil
                lastSync = Date()
            } catch HealthSync.SyncError.locked {
                healthLocked = true
                syncError = HealthSync.SyncError.locked.errorDescription
            } catch {
                syncError = error.localizedDescription
            }
        }
        if let sleep { exportFiles(sleep: sleep) }
        loadDashboard()
        loadCheckins()
        recompute()
        await report.reload()
        await wealth.refresh()
        loadFramework()
        await wealth.refreshEarnings(today: today)
    }

    func workoutRows() -> [WorkoutRow] {
        let entries = (try? context.fetch(FetchDescriptor<WorkoutEntry>(sortBy: [SortDescriptor(\.start)]))) ?? []
        return entries.map { WorkoutRow(start: $0.start, type: config.csvType(forActivity: $0.activity), minutes: $0.minutes) }
    }

    private func readings(_ kind: String) -> [DatedValue] {
        let all = (try? context.fetch(FetchDescriptor<HealthReading>(predicate: #Predicate { $0.kind == kind },
                                                                     sortBy: [SortDescriptor(\.date)]))) ?? []
        return all.map { DatedValue(date: $0.date, value: $0.value) }
    }

    /// Writes the five files the Mac reads. Only runs after a successful Health read, so a locked
    /// phone never replaces good files with empty ones.
    private func exportFiles(sleep: [SleepRow]) {
        guard folder.isLinked else { return }
        let writer = ExportWriter(formats: settings.formats, timeZone: .current)
        let base = settings.healthFolder
        // (file, content, rewrite every sync). build.py reads the modified time of the exercise
        // and sleep files to know Health has synced, so those two are always rewritten.
        let files: [(String, String, Bool)] = [
            ("workouts.csv", writer.workouts(workoutRows()), false),
            ("exercise_minutes.csv", writer.exerciseMinutes(exerciseMinutes ?? []), true),
            ("vo2max.csv", writer.vo2max(readings("vo2max")), false),
            ("weight.csv", writer.weight(readings("weight")), false),
            ("sleep_raw.txt", writer.sleep(sleep), true),
        ]
        for (name, text, always) in files {
            let path = "\(base)/\(name)"
            var status = fileStatus[path] ?? FileStatus()
            status.lastChecked = Date()
            // Never replace a file with nothing: an empty result means Health gave us no data.
            if text.isEmpty { status.lastError = "Nothing to write (no data from Health)."; fileStatus[path] = status; continue }
            do {
                if try folder.write(text, to: path, always: always) == .written { status.lastWrite = Date() }
                status.lastError = nil
            } catch {
                status.lastError = error.localizedDescription
            }
            fileStatus[path] = status
        }
        persist(fileStatus, "filestatus.json")
    }

    /// FitClub days from the Mac's ARX download, so Lift counts them as the Mac dashboard does.
    @discardableResult
    private func loadSessionDays() -> Bool {
        struct ARXSet: Decodable { var date: String?; var kind: String? }
        guard folder.isLinked, let data = try? folder.read("fitclub/sets.json"),
              let sets = try? JSONDecoder().decode([ARXSet].self, from: data) else { return false }
        let days = Set(sets.filter { $0.kind == "Main set" }.compactMap { $0.date.map { String($0.prefix(10)) } })
        if sessionDays["fitclub"] == days { return false }
        sessionDays["fitclub"] = days
        return true
    }

    func loadDashboard() {
        let sessionsChanged = loadSessionDays()
        guard folder.isLinked, let data = try? folder.read("data.json"),
              let decoded = try? DashboardData.decode(data) else { if sessionsChanged { recompute() }; return }
        if decoded != dashboard {
            dashboard = decoded
            recordPillars(decoded)
            recompute()
        } else if sessionsChanged {
            recompute()
        }
    }

    private func recompute() {
        let now = Date()
        statuses = HabitCounter.statuses(config: config, workouts: workoutRows(), exerciseMinutes: exerciseMinutes,
                                         mac: dashboard, planDays: report.planCount(today: GoalMath.dayString(now, calendar: calendar)),
                                         sessionDays: sessionDays, commitment: activeCommitment, now: now, calendar: calendar)
        var snapshot = WidgetSnapshot.make(config: config, statuses: statuses, mac: dashboard,
                                           todayString: GoalMath.dayString(now, calendar: calendar), now: now, calendar: calendar)
        snapshot.wealthLine = wealthNumber.map { "\($0.text) \($0.label)" }
        snapshot.wealthNext = wealth.holdings.isEmpty ? nil : Wealth.next(wealth.rows(today: today))
        if AppGroup.writeSnapshot(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Rebuilds the widget snapshot (called when Wealth's numbers change).
    func refreshWidgets() { recompute() }

    func rebuildFromHealth() async {
        health.resetAnchors()
        await sync()
    }

    // MARK: Today

    /// Today as yyyy-MM-dd, in the phone's time zone.
    var today: String { GoalMath.dayString(Date(), calendar: calendar) }

    var todayLine: String {
        let today = GoalMath.dayString(Date(), calendar: calendar)
        if let dashboard, dashboard.date == today, let line = dashboard.today, !line.isEmpty { return line }
        if let behind = HabitCounter.furthestBehind(statuses), let habit = config.habit(behind.key) { return habit.nudge + "." }
        return statuses.isEmpty ? config.goal.title : "All habits met."
    }

    var daysLeft: Int? { GoalMath.daysLeft(goal: config.goal, now: Date(), calendar: calendar) }
    var horizon: Double { GoalMath.horizon(goal: config.goal, now: Date(), calendar: calendar) }

    func status(_ key: String) -> HabitStatus? { statuses.first { $0.key == key } }

    /// Saves a workout to Apple Health, syncs, and leaves a one-line note on the bar it feeds.
    func log(_ habit: HabitDefinition, minutes: Int) async {
        guard let activity = habit.logsAs else { return }
        do {
            try await health.logWorkout(activity: activity, minutes: minutes)
            await sync()
            let done = Int(status(habit.key)?.value ?? 0)
            let goal = Int(habit.goal)
            let tail = done >= goal ? "\(done) of \(goal), goal met." : "\(done) of \(goal)."
            lastLogged = LoggedNote(pillar: habit.pillars.first ?? "", text: "\(habit.why) \(tail)")
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: check-in

    func loadCheckins() {
        guard folder.isLinked else { return }
        var file = CheckinsFile()
        if let data = try? folder.read("checkins.csv"), let text = String(data: data, encoding: .utf8) {
            file = CheckinsFile(text: text)
        }
        // In trial mode, show the app's own trial rows on top of the live history.
        if settings.trialMode, let data = try? folder.read(settings.checkinsPath),
           let text = String(data: data, encoding: .utf8) {
            for row in CheckinsFile(text: text).rows { file.save(date: row.date, values: row.values) }
        }
        checkins = file
    }

    var weekStart: Date {
        var cal = calendar
        cal.firstWeekday = 2   // Monday
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
    }

    /// This week's reading for a measurement, if one has been taken since Monday.
    func thisWeek(_ key: String) -> (date: String, value: Double)? {
        let start = GoalMath.dayString(weekStart, calendar: calendar)
        return checkins.history(key).last { $0.date >= start }
    }

    func saveMeasurement(_ measurement: MeasurementDefinition, value: Double) throws {
        let day = GoalMath.dayString(Date(), calendar: calendar)
        // Read the target file fresh, add or replace today's row, write the whole file back.
        var target = CheckinsFile()
        if folder.exists(settings.checkinsPath),
           let text = String(data: try folder.read(settings.checkinsPath), encoding: .utf8) {
            target = CheckinsFile(text: text)
        }
        target.save(date: day, values: [measurement.key: value])
        try folder.write(target.text, to: settings.checkinsPath)
        var status = fileStatus[settings.checkinsPath] ?? FileStatus()
        status.lastWrite = Date(); status.lastChecked = Date(); status.lastError = nil
        fileStatus[settings.checkinsPath] = status
        persist(fileStatus, "filestatus.json")

        let key = measurement.key
        let old = (try? context.fetch(FetchDescriptor<MeasurementEntry>(predicate: #Predicate { $0.key == key && $0.day == day }))) ?? []
        for entry in old { context.delete(entry) }
        context.insert(MeasurementEntry(key: key, day: day, value: value, provenance: Provenance.manual.rawValue,
                                        protocolLine: measurement.protocolLine, savedAt: Date()))
        try? context.save()
        loadCheckins()
    }

    /// The week in force today, if one was committed in the last 7 days.
    var activeCommitment: WeekRecord? { Commitments.active(commitments, on: today) }

    /// Replaces the saved weeks: SwiftData, then app/commitments.json for the Mac and the morning run.
    private func saveCommitments(_ records: [WeekRecord]) {
        commitments = records
        for old in (try? context.fetch(FetchDescriptor<CommitmentRecord>())) ?? [] { context.delete(old) }
        let base = Date()
        for (i, record) in records.enumerated() {
            guard let data = try? JSONEncoder().encode(record) else { continue }
            context.insert(CommitmentRecord(weekStart: record.week_start, weekEnd: record.week_end, record: data,
                                            savedAt: base.addingTimeInterval(Double(i) * 0.001)))
        }
        try? context.save()
        do { try folder.write(AppFiles.json(records), to: Commitments.file) } catch { syncError = error.localizedDescription }
        recompute()
    }

    /// Changes one habit's target for the current week only (from a long press on Today).
    func changeCommitment(_ key: String, target: Double, reason: String?) {
        saveCommitments(Commitments.change(commitments, today: today, habits: config.habits, key: key, target: target, reason: reason))
    }

    /// - targets: this week's target for any habit that differs from its usual goal.
    @discardableResult
    func commitWeek(habits: [String], reflection: String?, prompt: String, targets: [String: HabitCommitment] = [:]) -> WeekRecord? {
        saveCommitments(Commitments.commit(commitments, today: today, habits: config.habits, targets: targets))
        defer { try? context.save() }
        return commitWeekLegacy(habits: habits, reflection: reflection, prompt: prompt)
    }

    private func commitWeekLegacy(habits: [String], reflection: String?, prompt: String) -> WeekRecord? {
        context.insert(WeekCommitment(weekStart: GoalMath.dayString(weekStart, calendar: calendar), habitKeys: habits, date: Date()))
        if let reflection, !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.insert(Reflection(prompt: prompt, text: reflection, date: Date()))
        }
        try? context.save()
        return activeCommitment
    }

    // MARK: Monday reminder

    func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["checkin"])
        if settings.issueAlerts, !settings.reminderOn { center.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        guard settings.reminderOn else { return }
        #if DEBUG && targetEnvironment(simulator)
        if UserDefaults.standard.string(forKey: "demoFolder") != nil { return }   // no permission prompt over demo screens
        #endif
        let hour = settings.reminderHour, minute = settings.reminderMinute
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Check-in"
            content.body = "Measure when you're ready, any day this week."
            content.userInfo = ["link": DeepLink.checkin.absoluteString]
            var when = DateComponents()
            when.weekday = 2; when.hour = hour; when.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "checkin", content: content, trigger: trigger))
        }
    }

    func open(_ url: URL) {
        if url.isFileURL { importHoldings(from: url); return }
        let health = config.dashboardSection?.key ?? SectionDefinition.healthKey
        switch url.host {
        case "wealth": tab = .today; paths[.today] = wealth.holdings.isEmpty ? [] : [.section(Wealth.sectionKey)]
        case "watch":
            let ticker = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ticker" }?.value
            tab = .rituals; paths[.rituals] = ticker.flatMap { wealth.holding($0) }.map { [.watch($0.ticker)] } ?? []
        case "checkin": tab = .rituals; paths[.rituals] = [.checkin]
        case "report": tab = .today; paths[.today] = [.issue(health)]
        case "front": tab = .today; paths[.today] = []
        // The Health widgets open the Health dashboard.
        default: tab = .today; paths[.today] = [.section(health)]
        }
    }

    // MARK: small JSON files in Application Support

    static func supportURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    static func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: supportURL(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    func persist<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) { try? data.write(to: Self.supportURL(name), options: .atomic) }
    }
}
