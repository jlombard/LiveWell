import Foundation
import LiveWellCore

/// One ritual on the Rituals tab: a short ceremony tied to a section.
struct Ritual: Identifiable, Equatable {
    enum When: Equatable { case dueNow, comingUp, done }
    var id: String
    var when: When
    var section: String
    /// "Health · weekly"
    var kicker: String
    var title: String
    var detail: String
    /// yyyy-MM-dd it is due or was done (nil = now).
    var date: String?
    var route: Route?
}

/// One section's edition for today's front page.
struct EditionCover: Identifiable, Equatable {
    var id: String { section }
    var section: String
    var sectionName: String
    var edition: String
    var stories: Int
    var lead: String
    var date: String
    var unread: Bool
    /// Today's edition isn't here: nil, or what to say about it.
    var delayed: String?
}

extension AppModel {
    /// Pushes a screen in the current tab.
    func go(_ route: Route) { paths[tab, default: []].append(route) }

    // MARK: front page

    /// Marks a section's newest edition as read (the reader calls this when it appears).
    func markRead(_ section: String? = nil) {
        let main = config.dashboardSection?.key ?? SectionDefinition.healthKey
        let key = section ?? main
        if let date = report.edition(key == main ? "" : key).latest?.date, readIssues[key] != date { readIssues[key] = date }
    }

    /// Today's editions, one per section that has one. Separate editions, never a blended feed.
    var editions: [EditionCover] {
        let main = config.dashboardSection?.key ?? SectionDefinition.healthKey
        return config.sections.compactMap { section -> EditionCover? in
            guard let name = section.editionName else { return nil }
            let isMain = section.key == main
            guard let issue = report.edition(isMain ? "" : section.key).latest else {
                // A section that has never published is absent, except the main one, which says where issues come from.
                guard isMain, report.hasLoaded, folderLinked else { return nil }
                return EditionCover(section: section.key, sectionName: section.name, edition: name, stories: 0, lead: "", date: "",
                                    unread: false, delayed: "No editions found yet. They arrive in the Health Glance folder after the Mac\u{2019}s morning run.")
            }
            var delayed: String?
            if issue.date < today {
                // Fail loudly once the morning run should have finished; before that it is simply on its way.
                let hour = calendar.component(.hour, from: Date())
                delayed = hour < 8 ? "Today\u{2019}s edition is on its way. This is \(DayMath.weekdayName(issue.date))\u{2019}s."
                                   : "Today\u{2019}s edition didn\u{2019}t arrive. Check the morning run on the Mac. This is \(DayMath.weekdayName(issue.date))\u{2019}s."
            }
            return EditionCover(section: section.key, sectionName: section.name, edition: name, stories: issue.contentCards.count,
                                lead: issue.contentCards.first?.title ?? "", date: issue.date,
                                unread: readIssues[section.key] != issue.date, delayed: delayed)
        }
    }

    /// The newest edition's puzzle, while it is unplayed or in play.
    var puzzleExtra: (section: String, title: String, detail: String)? {
        let main = config.dashboardSection?.key ?? SectionDefinition.healthKey
        for section in config.sections where section.editionName != nil {
            guard let issue = report.edition(section.key == main ? "" : section.key).latest,
                  let card = issue.cards.first(where: { $0.puzzle?.isPlayable == true }) else { continue }
            let game = puzzles.games[issue.date]
            if game?.finished == true { continue }
            let day = DayMath.weekdayName(issue.date)
            let left = Puzzle.maxGuesses - (game?.guesses.count ?? 0)
            return (section.key, "\(day) puzzle: Name the company",
                    "\(section.name) · " + (game == nil ? "six guesses from a revenue map" : "\(left) \(left == 1 ? "guess" : "guesses") left")
                    + (card.puzzle?.number.map { " · No. \($0)" } ?? ""))
        }
        return nil
    }

    /// "About 2 minutes" for the editions not yet read (about half a minute a story).
    var readingTime: String? {
        let stories = editions.filter { $0.delayed == nil || $0.stories > 0 }.reduce(0) { $0 + $1.stories }
        guard stories > 0 else { return nil }
        let minutes = max(1, Int((Double(stories) * 0.5).rounded(.up)))
        return "About \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    // MARK: rituals

    /// "Mon 16" within two weeks either way, otherwise "Dec 1".
    private func ritualDay(_ day: String) -> String {
        if let a = DayMath.date(day), let b = DayMath.date(today), abs(a.timeIntervalSince(b)) > 14 * 86_400 { return shortDay(day) }
        return "\(DayMath.weekdayName(day).prefix(3)) \(Int(day.suffix(2)) ?? 0)"
    }

    /// Due now, coming up and done recently, across sections. Only Health has rituals today.
    var rituals: [Ritual] {
        guard let section = config.dashboardSection, !section.measurements.isEmpty || !section.habits.isEmpty else { return [] }
        let name = section.name
        var out: [Ritual] = []
        let monday = GoalMath.dayString(weekStart, calendar: calendar)
        let nextMonday = DayMath.adding(7, to: monday) ?? monday
        let measured = section.measurements.filter { thisWeek($0.key) != nil }.count
        let total = section.measurements.count
        let committedThisWeek = commitments.last.map { $0.week_start >= monday } ?? false

        if folderLinked {
            if measured < total {
                out.append(Ritual(id: "checkin", when: .dueNow, section: section.key, kicker: "\(name) · weekly", title: "Check-in",
                                  detail: "\(measured) of \(total) measured · then commit to the week", route: .checkin))
            } else if !committedThisWeek {
                out.append(Ritual(id: "commit", when: .dueNow, section: section.key, kicker: "\(name) · weekly", title: "Commit to the week",
                                  detail: reviewDue ? "All \(total) measured · the plan review follows" : "All \(total) measured", route: .checkin))
            }
        }
        out.append(Ritual(id: "next-checkin", when: .comingUp, section: section.key, kicker: name, title: "Weekly check-in",
                          detail: "", date: nextMonday))
        let lastReview = UserDefaults.standard.string(forKey: "lastPlanReview")
        let reviewDay = lastReview.flatMap { DayMath.adding(14, to: $0) }.map { max($0, monday) } ?? monday
        // The review follows a check-in, so it lands on a Monday.
        let reviewMonday = reviewDay <= monday ? (committedThisWeek ? nextMonday : monday) : (reviewDay <= nextMonday ? nextMonday : DayMath.adding(14, to: monday) ?? nextMonday)
        // A review that rides with this week's commit is named on the due card, not listed as upcoming.
        if reviewMonday > today {
            out.append(Ritual(id: "next-review", when: .comingUp, section: section.key, kicker: name, title: "Plan review",
                              detail: "", date: reviewMonday))
        }

        if let week = commitments.last {
            let lighter = week.isLighter ? "a lighter week" : "all \(week.habits.count)"
            out.append(Ritual(id: "done-commit", when: .done, section: section.key, kicker: name,
                              title: "Committed to the week · \(lighter)", detail: "", date: week.week_start))
        }
        if let lastReview {
            out.append(Ritual(id: "done-review", when: .done, section: section.key, kicker: name, title: "Plan review", detail: "", date: lastReview))
        }
        let lastMeasured = section.measurements.compactMap { checkins.history($0.key).last?.date }.max()
        if let lastMeasured {
            let n = section.measurements.filter { checkins.history($0.key).last?.date == lastMeasured }.count
            out.append(Ritual(id: "done-checkin", when: .done, section: section.key, kicker: name,
                              title: "Check-in · \(n) measured", detail: "", date: lastMeasured))
        }
        // Until every holding has written reasons: one to-do, naming the next holding.
        let rows = wealth.rows(today: today)
        if let next = rows.first(where: { $0.status == .notWritten }) {
            let unwritten = rows.filter { $0.status == .notWritten }.count
            out.append(Ritual(id: "write-\(next.ticker)", when: .dueNow, section: Wealth.sectionKey,
                              kicker: "Wealth · until all \(rows.count) are written", title: "Write why you own \(next.name)",
                              detail: ask.state(AskStore.key(Wealth.sectionKey, next.ticker)) == .ready ? "Answer ready in Ask"
                                  : (ask.state(AskStore.key(Wealth.sectionKey, next.ticker)) == .answering ? "Ask is answering\u{2026}"
                                  : (next.next == "Write why you own it" ? "\(unwritten) of \(rows.count) still to write" : next.next)),
                              route: .ask(Wealth.sectionKey, next.ticker)))
        }
        for r in wealth.reasons.values where r.source == "app" {
            out.append(Ritual(id: "done-reasons-\(r.ticker)", when: .done, section: Wealth.sectionKey, kicker: "Wealth",
                              title: "Wrote why you own \(r.name)", detail: "", date: r.written))
        }
        if !wealth.holdings.isEmpty, let first = DayMath.adding(1, to: today).map({ _ in String(today.prefix(8)) + "01" }),
           let next = DayMath.adding(32, to: first).map({ String($0.prefix(8)) + "01" }) {
            out.append(Ritual(id: "holdings-refresh", when: .comingUp, section: Wealth.sectionKey, kicker: "Wealth",
                              title: "Holdings refresh", detail: "", date: next))
            if let imported = wealth.importedOn {
                out.append(Ritual(id: "done-holdings", when: .done, section: Wealth.sectionKey, kicker: "Wealth",
                                  title: "Imported \(wealth.holdings.count) holdings", detail: "", date: imported))
            }
        }
        return out
    }

    func ritualDate(_ ritual: Ritual) -> String { ritual.date.map(ritualDay) ?? "" }
}
