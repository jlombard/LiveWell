import Foundation
import Observation
import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit
import SurfCore

enum AppTab: Hashable { case today, report, checkin }

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
    static let refreshTaskID = "surfat60.refresh"

    let container: ModelContainer
    let health = HealthSync()
    let folder = HealthGlanceFolder()

    var config: SurfConfig { didSet { if config != oldValue { persist(config, "config.json"); recompute() } } }
    var settings: AppSettings { didSet { if settings != oldValue { persist(settings, "settings.json"); scheduleReminder() } } }

    private(set) var dashboard: DashboardData?
    private(set) var statuses: [HabitStatus] = []
    private(set) var checkins = CheckinsFile()
    private(set) var fileStatus: [String: FileStatus] = [:]
    private(set) var lastSync: Date?
    private(set) var syncError: String?
    private(set) var isSyncing = false
    private(set) var healthLocked = false
    private(set) var folderLinked = false

    var tab: AppTab = .today
    var lastLogged: LoggedNote?

    private var exerciseMinutes: [DatedValue]?
    private var syncAgain = false

    var context: ModelContext { container.mainContext }
    var calendar: Calendar { Calendar.current }

    init() {
        container = try! ModelContainer(for: WorkoutEntry.self, HealthReading.self, MeasurementEntry.self,
                                        Reflection.self, WeekCommitment.self)
        config = Self.load("config.json") ?? .default
        settings = Self.load("settings.json") ?? AppSettings()
        fileStatus = Self.load("filestatus.json") ?? [:]
        exerciseMinutes = Self.load("exercise.json")
        folderLinked = folder.isLinked
        folder.onDashboardChange = { [weak self] in self?.loadDashboard() }
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
            Task { await sync() }
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

    func loadDashboard() {
        guard folder.isLinked, let data = try? folder.read("data.json"),
              let decoded = try? DashboardData.decode(data) else { return }
        if decoded != dashboard {
            dashboard = decoded
            recompute()
        }
    }

    private func recompute() {
        let now = Date()
        statuses = HabitCounter.statuses(config: config, workouts: workoutRows(), exerciseMinutes: exerciseMinutes,
                                         mac: dashboard, now: now, calendar: calendar)
        let snapshot = WidgetSnapshot.make(config: config, statuses: statuses, mac: dashboard,
                                           todayString: GoalMath.dayString(now, calendar: calendar), now: now)
        if AppGroup.writeSnapshot(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
    }

    func rebuildFromHealth() async {
        health.resetAnchors()
        await sync()
    }

    // MARK: Today

    var todayLine: String {
        let today = GoalMath.dayString(Date(), calendar: calendar)
        if let dashboard, dashboard.date == today, let line = dashboard.today, !line.isEmpty { return line }
        if let behind = HabitCounter.furthestBehind(statuses), let habit = config.habit(behind.key) { return habit.nudge + "." }
        return statuses.isEmpty ? config.goal.title : "All five met."
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

    func commitWeek(habits: [String], reflection: String?, prompt: String) {
        context.insert(WeekCommitment(weekStart: GoalMath.dayString(weekStart, calendar: calendar), habitKeys: habits, date: Date()))
        if let reflection, !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.insert(Reflection(prompt: prompt, text: reflection, date: Date()))
        }
        try? context.save()
    }

    // MARK: Monday reminder

    func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["checkin"])
        guard settings.reminderOn else { return }
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
            center.add(UNNotificationRequest(identifier: "checkin", content: content, trigger: trigger))
        }
    }

    func open(_ url: URL) {
        switch url.host {
        case "checkin": tab = .checkin
        case "report": tab = .report
        default: tab = .today
        }
    }

    // MARK: small JSON files in Application Support

    private static func supportURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: supportURL(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private func persist<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) { try? data.write(to: Self.supportURL(name), options: .atomic) }
    }
}
