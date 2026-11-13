import Foundation
import SwiftData
import UIKit
import UserNotifications
import LiveWellCore

/// What the Review screen shows.
struct ReviewData {
    var habits: [PlanReview.HabitWeeks]
    var pillars: [PlanReview.PillarTrend]
    var proposal: PlanReview.Proposal

    /// The same facts as plain lines, saved with the decision for the morning run.
    var evidence: [String] {
        habits.map { h in
            let weeks = zip(h.weeks, h.planned).map { value, plan in
                (value.map(formatValue) ?? "not measured") + (plan.map { " (\($0))" } ?? "")
            }.joined(separator: ", then ")
            return "\(h.name): \(weeks) against a usual goal of \(formatValue(h.goal))"
        } + pillars.map { p in
            guard let to = p.to else { return "\(p.label): not measured" }
            guard let from = p.from else { return "\(p.label): \(formatValue(to)), not enough history for a 4-week trend" }
            return "\(p.label): \(formatValue(from)) to \(formatValue(to)) over about 4 weeks (\(p.trend.rawValue))"
        }
    }
}

extension AppModel {
    private static let lastReviewKey = "lastPlanReview"
    /// Health readings that are a pillar's value directly.
    private static let healthPillars = ["cardio": "vo2max"]

    // MARK: pillar history

    /// Keeps each pillar's value by the day it was measured, so trends can be read later.
    func recordPillars(_ data: DashboardData) {
        var history = pillarHistory
        for pillar in data.pillars {
            guard let value = pillar.value, let day = pillar.as_of ?? data.date else { continue }
            history[pillar.key, default: [:]][String(day.prefix(10))] = value
        }
        if history != pillarHistory { pillarHistory = history; persist(history, "pillars.json") }
    }

    private func history(for pillar: String) -> [(date: String, value: Double)] {
        var points = pillarHistory[pillar] ?? [:]
        // Measurements taken at check-in and readings from Health go back further than the app's own record.
        for m in config.measurements where m.pillar == pillar {
            for reading in checkins.history(m.key) { points[reading.date] = reading.value }
        }
        if let kind = Self.healthPillars[pillar] {
            let all = (try? context.fetch(FetchDescriptor<HealthReading>(predicate: #Predicate { $0.kind == kind },
                                                                         sortBy: [SortDescriptor(\.date)]))) ?? []
            for r in all { points[GoalMath.dayString(r.date, calendar: calendar)] = r.value }   // sorted, so the latest of a day wins
        }
        return points.map { (date: $0.key, value: $0.value) }
    }

    // MARK: the review

    var reviewDue: Bool { PlanReview.isDue(lastReview: UserDefaults.standard.string(forKey: Self.lastReviewKey), today: today) }

    func planReview() -> ReviewData {
        let now = Date()
        let earlier = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let rows = workoutRows()
        // The commitment in force at the end of each week; a changed target marks that week as planned.
        func planned(_ habit: HabitDefinition, ending end: Date) -> String? {
            guard let c = Commitments.active(commitments, on: GoalMath.dayString(end, calendar: calendar))?.habits[habit.key],
                  c.target != habit.goal else { return nil }
            return "\(formatValue(c.target)) planned" + (c.reason.map { ", \($0)" } ?? "")
        }
        func week(ending end: Date, mac: DashboardData?) -> [HabitStatus] {
            HabitCounter.statuses(config: config, workouts: rows, exerciseMinutes: exerciseMinutesForReview, mac: mac,
                                  planDays: report.planCount(today: GoalMath.dayString(end, calendar: calendar)), sessionDays: sessionDays,
                                  now: end, calendar: calendar)
        }
        let first = week(ending: earlier, mac: nil), second = week(ending: now, mac: dashboard)
        let habits = config.habits.map { habit in
            PlanReview.HabitWeeks(key: habit.key, name: habit.name, goal: habit.goal,
                                  weeks: [first.first { $0.key == habit.key }?.value, second.first { $0.key == habit.key }?.value],
                                  pillars: habit.pillars, planned: [planned(habit, ending: earlier), planned(habit, ending: now)])
        }
        let settingsText = (try? folder.read("settings.json")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let pillars = (dashboard?.pillars ?? []).map { p -> PlanReview.PillarTrend in
            let lower = (p.from ?? 0) > (p.goal ?? 0)
            let span = abs((p.goal ?? 0) - (p.from ?? 0))
            let t = PlanReview.trend(history: history(for: p.key), today: today, lowerIsBetter: lower, span: span)
            let goal = JSONText.number(at: ["pillars", p.key, "goal"], in: settingsText) ?? p.goal
            let next = JSONText.number(at: ["pillars", p.key, "next_goal"], in: settingsText)
            var reached = p.reached ?? false
            if let value = p.value, let goal { reached = reached || (lower ? value <= goal : value >= goal) }
            return PlanReview.PillarTrend(key: p.key, label: p.label, trend: t.trend, from: t.from, to: p.value ?? t.to,
                                          goal: goal, nextGoal: next, reached: reached)
        }
        return ReviewData(habits: habits, pillars: pillars, proposal: PlanReview.propose(habits: habits, pillars: pillars))
    }

    /// Records the choice and, when accepted, makes the change: a new dated plan version in
    /// config.json, and the goal written into the Mac's settings.json so every screen agrees.
    /// - decision: "accept", "not_now", "no", or "stay".
    func decide(_ review: ReviewData, decision: String, reason: String) -> String? {
        let proposal = review.proposal
        var problem: String?
        if decision == "accept", proposal.isChange {
            let section = config.dashboardSection?.key ?? SectionDefinition.healthKey
            var updated = config
            let path: [String]
            if proposal.kind == "habit" {
                if let i = updated.habits.firstIndex(where: { $0.key == proposal.key }) { updated.habits[i].goal = proposal.to }
                path = ["habits_last_7_days", proposal.key, "goal"]
            } else {
                if let i = updated.sections.firstIndex(where: { $0.key == section }) { updated.sections[i].pillarGoals[proposal.key] = proposal.to }
                path = ["pillars", proposal.key, "goal"]
            }
            updated.planHistory.append(PlanVersion(date: today, section: section, kind: proposal.kind, key: proposal.key,
                                                   from: proposal.from, to: proposal.to, summary: proposal.headline + " " + proposal.reason))
            config = updated
            do {
                guard let text = String(data: try folder.read("settings.json"), encoding: .utf8),
                      let edited = JSONText.setting(proposal.to, at: path, in: text) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try folder.write(edited, to: "settings.json")
            } catch {
                problem = "Saved in the app, but the Mac's settings.json couldn't be updated: \(error.localizedDescription)"
            }
        }
        // Append to the decisions file for the morning run.
        var decisions: [PlanReview.Decision] = []
        if let data = try? folder.read(PlanReview.file) { decisions = (try? JSONDecoder().decode([PlanReview.Decision].self, from: data)) ?? [] }
        decisions.append(PlanReview.Decision(date: today, section: config.dashboardSection?.key ?? SectionDefinition.healthKey,
                                             proposal: proposal, decision: decision,
                                             reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
                                             evidence: review.evidence, at: ReportStore.now()))
        _ = try? folder.write(AppFiles.json(decisions), to: PlanReview.file)
        UserDefaults.standard.set(today, forKey: Self.lastReviewKey)
        return problem
    }

    // MARK: cutover

    /// Turning trial mode off: the Watch automations' log is retired, so it can't be counted on top
    /// of the app's own workouts file.
    func finishCutover() {
        do {
            cutoverNote = try folder.move("health/workouts_log.csv", to: "health/old/workouts_log.csv")
                ? "Moved health/workouts_log.csv to health/old/." : nil
        } catch {
            cutoverNote = "Couldn't move health/workouts_log.csv: \(error.localizedDescription). Move it to health/old/ by hand."
        }
    }

    // MARK: new-issue notification

    /// One notification for all of the day's editions, sent as soon as they are ready, unless the
    /// app is in front. A later edition the same morning updates it instead of adding a second.
    func announce(_ issue: ReportIssue, section: String? = nil) {
        guard settings.issueAlerts, UIApplication.shared.applicationState != .active else { return }
        let ready = editions.filter { $0.date == today && $0.stories > 0 }
        let content = UNMutableNotificationContent()
        content.title = ready.count > 1 ? "Your editions are ready" : "\(ready.first?.edition ?? "Your edition") is ready"
        var parts = [issue.contentCards.first.map { RichText.plain($0.title) } ?? "Today\u{2019}s issue is here."]
        // An ongoing to-do (writing reasons) is mentioned at most once a week; the Rituals tab carries the badge.
        let rows = wealth.rows(today: today)
        let todo = rows.filter { $0.status == .notWritten }.count
        let lastNudge = UserDefaults.standard.string(forKey: "lastWealthNudge")
        if todo > 0, lastNudge.flatMap({ DayMath.adding(7, to: $0) }).map({ $0 <= today }) ?? true {
            parts.append("Wealth: 1 thing to do")
            UserDefaults.standard.set(today, forKey: "lastWealthNudge")
        }
        content.body = parts.joined(separator: " · ")
        let link = section == Wealth.sectionKey && ready.count == 1 ? DeepLink.wealth : (ready.count > 1 ? DeepLink.front : DeepLink.report)
        content.userInfo = ["link": link.absoluteString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "editions-\(today)", content: content, trigger: nil))
    }
}
