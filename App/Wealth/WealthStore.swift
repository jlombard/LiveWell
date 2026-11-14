import Foundation
import Observation
import UserNotifications
import LiveWellCore

/// One closing quote from Finnhub: GET /quote?symbol=AAPL → c (current or last price),
/// pc (previous close), t (time of the quote). Daily history is a paid endpoint, so the app
/// keeps its own record of closes.
enum Finnhub {
    struct Quote: Decodable { var c: Double; var pc: Double; var t: Double }

    enum Failure: LocalizedError {
        case noKey, badKey, limited, other(Int)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your Finnhub key in Settings to get closing prices."
            case .badKey: return "Finnhub didn\u{2019}t accept that key. Check it in Settings."
            case .limited: return "Finnhub\u{2019}s rate limit was reached. Prices will be checked again later."
            case .other(let code): return "Finnhub returned an error (\(code))."
            }
        }
    }

    /// GET /calendar/earnings?from=…&to=…&symbol=AAPL → earningsCalendar: [{date, hour, symbol, …}].
    /// On the free plan: a month back and what is coming.
    static func earnings(_ symbol: String, from: String, to: String, key: String) async throws -> [EarningsDate] {
        struct Row: Decodable { var date: String?; var hour: String?; var symbol: String? }
        struct Body: Decodable { var earningsCalendar: [Row]? }
        var components = URLComponents(string: "https://finnhub.io/api/v1/calendar/earnings")!
        components.queryItems = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to), URLQueryItem(name: "symbol", value: symbol)]
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "X-Finnhub-Token")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            let rows = (try JSONDecoder().decode(Body.self, from: data)).earningsCalendar ?? []
            return rows.compactMap { r in r.date.map { EarningsDate(ticker: symbol, date: $0, hour: (r.hour ?? "").isEmpty ? nil : r.hour) } }
        case 401, 403: throw Failure.badKey
        case 429: throw Failure.limited
        case let code: throw Failure.other(code)
        }
    }

    static func quote(_ symbol: String, key: String) async throws -> Quote {
        var components = URLComponents(string: "https://finnhub.io/api/v1/quote")!
        components.queryItems = [URLQueryItem(name: "symbol", value: symbol)]
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "X-Finnhub-Token")   // the key stays out of the URL
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return try JSONDecoder().decode(Quote.self, from: data)
        case 401, 403: throw Failure.badKey
        case 429: throw Failure.limited
        case let code: throw Failure.other(code)
        }
    }
}

/// Wealth on the phone: holdings from the brokerage CSV and a record of daily closes.
/// Both stay in the app's own storage; only percentages go to the Health Glance folder.
@MainActor
@Observable
final class WealthStore {
    private(set) var holdings: [Holding] = []
    private(set) var book = PriceBook()
    private(set) var importedOn: String?
    private(set) var isRefreshing = false
    /// The last problem, in plain words (shown in Settings).
    private(set) var note: String?
    private var lastAttempt: Date?
    var onChange: () -> Void = {}

    /// Written reasons, by ticker, and drafts in progress.
    private(set) var reasons: [String: Reasons] = [:]
    private(set) var drafts: [String: ReasonsDraft] = [:]

    /// Earnings dates, from Finnhub and from the morning run's calendar file.
    private(set) var earnings: [EarningsDate] = []
    /// What the rituals have recorded: watch notes, "Still true?" checks, leadership checks.
    private(set) var record = WealthRecord()
    private var earningsFetched: String?

    private struct Saved: Codable {
        var holdings: [Holding]; var importedOn: String?; var book: PriceBook
        var reasons: [String: Reasons]?; var drafts: [String: ReasonsDraft]?
        var earnings: [EarningsDate]?; var record: WealthRecord?
    }
    private static let fileName = "wealth.json"

    init() {
        if let saved: Saved = AppModel.load(Self.fileName) {
            // Cash positions imported by an earlier build are dropped.
            holdings = saved.holdings.filter { !HoldingsCSV.isCash($0.name) }; importedOn = saved.importedOn; book = saved.book
            reasons = saved.reasons ?? [:]; drafts = saved.drafts ?? [:]
            earnings = saved.earnings ?? []; record = saved.record ?? WealthRecord()
        }
        #if DEBUG && targetEnvironment(simulator)
        // Simulator only: `-demoHoldings <csv> -demoPrices <json>` show Wealth without a key or a real export.
        let d = UserDefaults.standard
        if let path = d.string(forKey: "demoHoldings"), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            holdings = HoldingsCSV.parse(text); importedOn = "2026-10-30"
            var demo = ReasonsDraft(ticker: "AAPL"); demo.lensesDone = ["problem", "model", "users"]
            demo.approve(.reason, "Its customers stay by choice, and spend more each year.", lens: "users", id: "d1")
            drafts = ["AAPL": demo]
            if let prices = d.string(forKey: "demoPrices"), let data = FileManager.default.contents(atPath: prices),
               let demo = try? JSONDecoder().decode(PriceBook.self, from: data) { book = demo }
        }
        #endif
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(Saved(holdings: holdings, importedOn: importedOn, book: book, reasons: reasons, drafts: drafts, earnings: earnings, record: record)) {
            try? data.write(to: AppModel.supportURL(Self.fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        onChange()
    }

    static var newYork: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c
    }

    func rows(today: String) -> [Wealth.Row] {
        var rows = Wealth.board(holdings, book, today: today, written: Set(reasons.keys),
                                started: drafts.filter { !$0.value.lines.isEmpty || !$0.value.lensesDone.isEmpty }.mapValues { $0.lensesDone.count })
        // A written holding's status comes from his latest "Still true?" check, then from a leadership check.
        for i in rows.indices where rows[i].status != .notWritten {
            let ticker = rows[i].ticker
            if let check = record.latestCheck(ticker) {
                rows[i].status = check.outcome.status; rows[i].next = check.outcome.next
            }
            if let values = record.latestValues(ticker), values.answers.contains(where: { $0 != .yes }), rows[i].status == .stillTrue,
               values.date >= (record.latestCheck(ticker)?.date ?? "") {
                rows[i].status = .check(values.line); rows[i].next = values.line
            }
            if let report = WealthRituals.checkDue(earnings, record, ticker: ticker, today: today) {
                rows[i].next = "Reported \(shortDay(report.date)) · \u{201C}Still true?\u{201D} check due"
            } else if let report = WealthRituals.next(earnings, ticker, today: today), let soon = DayMath.adding(14, to: today), report.date <= soon {
                rows[i].next = "Reports \(shortDay(report.date))" + (report.when.map { " \($0)" } ?? "")
            }
        }
        // An unwritten holding still shows a report that is close.
        for i in rows.indices where rows[i].status == .notWritten && rows[i].next == "Write why you own it" {
            if let report = WealthRituals.next(earnings, rows[i].ticker, today: today), let soon = DayMath.adding(7, to: today), report.date <= soon {
                rows[i].next = "Reports \(shortDay(report.date)) · reasons not written yet"
            }
        }
        return rows
    }

    func saveWatch(_ note: WatchNote) {
        record.watch.removeAll { $0.ticker == note.ticker && $0.earnings == note.earnings }
        record.watch.append(note); save()
    }

    func saveCheck(_ check: StillTrueCheck) { record.checks.append(check); save() }
    func saveValues(_ check: ValuesCheck) { record.values.append(check); save() }

    /// Dates the morning run looked up (investor-relations pages), merged with Finnhub's.
    func adoptCalendar(_ dates: [EarningsDate]) {
        let merged = WealthRituals.merge(earnings, dates.filter { d in holdings.contains { $0.ticker == d.ticker } })
        if merged != earnings { earnings = merged; save() }
    }

    /// Asks Finnhub for each holding's earnings dates, at most once a day.
    func refreshEarnings(today: String) async {
        guard !holdings.isEmpty, earningsFetched != today, let key = Keychain.finnhubKey, !key.isEmpty,
              let from = DayMath.adding(-28, to: today), let to = DayMath.adding(60, to: today) else { return }
        earningsFetched = today
        var found: [EarningsDate] = []
        for holding in holdings {
            if let dates = try? await Finnhub.earnings(holding.ticker, from: from, to: to, key: key) { found += dates }
        }
        // Keep older dates already known; refresh what the service reports now.
        let merged = WealthRituals.merge(found, earnings)
        if merged != earnings { earnings = merged; save() }
    }

    func holding(_ ticker: String) -> Holding? { holdings.first { $0.ticker == ticker } }

    func draft(_ ticker: String) -> ReasonsDraft {
        drafts[ticker] ?? reasons[ticker].map(ReasonsDraft.init(revising:)) ?? ReasonsDraft(ticker: ticker)
    }

    func setDraft(_ draft: ReasonsDraft) { drafts[draft.ticker] = draft; save() }

    /// The draft becomes his written reasons. Returns false when it isn't complete yet.
    @discardableResult
    func saveReasons(_ ticker: String, today: String) -> Bool {
        guard let holding = holding(ticker), let written = draft(ticker).reasons(name: holding.displayName, today: today) else { return false }
        reasons[ticker] = written
        save()
        return true
    }

    /// Reasons read from investment-framework.md fill in holdings he hasn't written in the app.
    func adopt(_ fromFramework: [Reasons]) {
        var changed = false
        for var r in fromFramework where holding(r.ticker) != nil {
            if let existing = reasons[r.ticker] {
                guard existing.source == "framework" else { continue }     // his own words in the app win
                r.written = existing.written
                if existing == r { continue }
            }
            reasons[r.ticker] = r; changed = true
        }
        if changed { save() }
    }

    /// Replaces the holdings with the file's. Returns how many were read (0 = nothing recognised, nothing changed).
    @discardableResult
    func importCSV(_ text: String, today: String) -> Int {
        let parsed = HoldingsCSV.parse(text)
        guard !parsed.isEmpty else {
            note = "That file didn\u{2019}t have a Symbol and a Quantity column, so nothing was imported."
            return 0
        }
        holdings = parsed; importedOn = today; note = nil
        save()
        Task { await refresh(force: true) }
        return parsed.count
    }

    func report(_ message: String) { note = message }

    func clear() {
        holdings = []; book = PriceBook(); importedOn = nil; note = nil
        save()
    }

    /// Records closing prices. Runs at most once after each US close (about one call per holding
    /// per trading day), unless forced from Settings.
    func refresh(force: Bool = false) async {
        guard !holdings.isEmpty, !isRefreshing else { return }
        guard let key = Keychain.finnhubKey, !key.isEmpty else { note = Finnhub.Failure.noKey.errorDescription; return }
        let cal = Self.newYork, now = Date()
        let today = GoalMath.dayString(now, calendar: cal)
        let weekday = cal.component(.weekday, from: now)
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let isWeekday = (2...6).contains(weekday)
        let open = isWeekday && minutes >= 9 * 60 + 30 && minutes < 16 * 60 + 10
        // The latest session that has closed.
        let lastClosed = isWeekday && minutes >= 16 * 60 + 10 ? today : Wealth.previousTradingDay(today)
        let missing = holdings.contains { book.closes[$0.ticker]?[lastClosed] == nil }
        if !force {
            guard missing else { return }
            // A market holiday never gets a close; don't ask again for a few hours.
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < 4 * 3600 { return }
        }
        isRefreshing = true
        defer { isRefreshing = false }
        lastAttempt = now
        var problem: String?
        var updated = book
        for holding in holdings {
            do {
                let q = try await Finnhub.quote(holding.ticker, key: key)
                guard q.c > 0 else { problem = "Finnhub has no price for \(holding.ticker)."; continue }
                let quoteDay = GoalMath.dayString(Date(timeIntervalSince1970: q.t), calendar: cal)
                if open {
                    // Mid-session the current price isn't a close; only yesterday's close is kept.
                    updated.record(holding.ticker, day: Wealth.previousTradingDay(today), close: q.pc)
                } else {
                    updated.record(holding.ticker, day: quoteDay, close: q.c)
                    updated.record(holding.ticker, day: Wealth.previousTradingDay(quoteDay), close: q.pc)
                }
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if case Finnhub.Failure.badKey = error { break }
                if case Finnhub.Failure.limited = error { break }
            }
        }
        note = problem
        if updated != book { book = updated; save() }
    }
}

extension AppModel {
    /// "+2.1%" and "this week" (or "since Wed", or "today"), for the front page and the widgets.
    var wealthNumber: (text: String, label: String)? {
        guard !wealth.holdings.isEmpty else { return nil }
        if settings.wealthDaily {
            return Wealth.day(wealth.holdings, wealth.book, today: today).map { (Wealth.percentText($0), "on the day") }
        }
        guard let week = Wealth.week(wealth.holdings, wealth.book, today: today) else { return nil }
        return (Wealth.percentText(week.percent), week.since.map { "since \(DayMath.weekdayName($0).prefix(3))" } ?? "this week")
    }

    /// Holdings or prices changed: make sure the section exists, refresh the widgets, and tell the morning run.
    func wealthChanged() {
        let has = !wealth.holdings.isEmpty
        if has, config.section(Wealth.sectionKey) == nil {
            config.sections.append(SectionDefinition(key: Wealth.sectionKey, name: "Wealth", icon: "building.columns",
                                                     accent: SectionDefinition.defaultAccent, edition: "Build Wealth"))
        } else if !has, config.section(Wealth.sectionKey) != nil {
            config.sections.removeAll { $0.key == Wealth.sectionKey }
        }
        refreshWidgets()
        scheduleEarningsReminders()
        guard folder.isLinked else { return }
        if has {
            let week = Wealth.week(wealth.holdings, wealth.book, today: today)
            let summary = Wealth.Summary(rows: wealth.rows(today: today), week: week.map { ($0.percent, $0.since) },
                                         pricesAsOf: wealth.book.latestDay, updated: ReportStore.now())
            _ = try? folder.write(AppFiles.json(summary), to: Wealth.file)
            // His written reasons, for the morning run. Words only: no shares, no prices.
            let written = wealth.holdings.compactMap { wealth.reasons[$0.ticker] }
            if !written.isEmpty { _ = try? folder.write(AppFiles.json(written), to: Reasons.file) }
            // What the rituals recorded, so the next issue can use it.
            if wealth.record != WealthRecord() { _ = try? folder.write(AppFiles.json(wealth.record), to: WealthRecord.file) }
        }
    }

    /// Reads theses already written in investment-framework.md (ASML today) into the board, and
    /// earnings dates the morning run has looked up.
    func loadFramework() {
        guard folder.isLinked, !wealth.holdings.isEmpty else { return }
        if let data = try? folder.read("investment-framework.md"), let text = String(data: data, encoding: .utf8) {
            wealth.adopt(FrameworkDoc.reasons(in: text, today: today))
        }
        if let data = try? folder.read(WealthRituals.calendarFile), let dates = try? JSONDecoder().decode([EarningsDate].self, from: data) {
            wealth.adoptCalendar(dates)
        }
    }

    /// One notification the morning before each report: something new that needs him.
    func scheduleEarningsReminders() {
        let center = UNUserNotificationCenter.current()
        guard settings.issueAlerts else { return }
        // Clear any reminder already set for a known date; the ones still needed are added again below.
        center.removePendingNotificationRequests(withIdentifiers: wealth.earnings.map { "watch-\($0.ticker)-\($0.date)" })
        for holding in wealth.holdings {
            guard let report = WealthRituals.next(wealth.earnings, holding.ticker, today: today),
                  wealth.record.note(holding.ticker, earnings: report.date) == nil,
                  let dayBefore = DayMath.adding(-1, to: report.date), dayBefore >= today else { continue }
            let p = dayBefore.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { continue }
            var when = DateComponents(); when.year = p[0]; when.month = p[1]; when.day = p[2]; when.hour = 9
            if dayBefore == today, calendar.component(.hour, from: Date()) >= 9 { continue }
            let content = UNMutableNotificationContent()
            content.title = "What to watch: \(holding.displayName)"
            content.body = "\(holding.displayName) reports tomorrow\(report.when.map { " \($0)" } ?? ""). Two minutes now to write what would change your mind."
            content.userInfo = ["link": "livewell://watch?ticker=\(holding.ticker)"]
            center.add(UNNotificationRequest(identifier: "watch-\(holding.ticker)-\(report.date)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
    }

    /// Reads a brokerage CSV picked in Settings or shared to the app.
    func importHoldings(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            wealth.report("That file couldn\u{2019}t be read.")
            return
        }
        if wealth.importCSV(text, today: today) > 0 {
            loadFramework()
            if tab == .today { paths[.today] = [.section(Wealth.sectionKey)] }
        }
        // A file shared to the app is copied into its Inbox; it holds account details, so remove the copy.
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
    }
}
