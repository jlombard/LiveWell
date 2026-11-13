import Foundation
import Observation
import LiveWellCore

/// The Surf Report on the phone: issues read from newsletter/issues, the food check-in,
/// votes and kept answers. The Mac writes the issues; the app owns the other three files.
@MainActor
@Observable
final class ReportStore {
    private let folder: HealthGlanceFolder
    private var cache: [String: (modified: Date, issue: ReportIssue)] = [:]
    private var loading = false
    private var loadAgain = false

    private(set) var issues: [String: ReportIssue] = [:]
    private(set) var archive = ReportArchive()
    /// The other sections' editions (Build Wealth), by section key. Each has its own folder.
    struct Edition: Equatable { var issues: [String: ReportIssue] = [:]; var archive = ReportArchive()
        var latest: ReportIssue? { archive.issues.first.flatMap { issues[$0.date] } } }
    private(set) var others: [String: Edition] = [:]
    /// Set by AppModel: section key → issues folder, for every section with an edition besides Health.
    var otherFolders: () -> [String: String] = { [:] }

    /// A section's edition; Health's (or an unknown key's) is the original one.
    func edition(_ section: String) -> Edition { others[section] ?? Edition(issues: issues, archive: archive) }
    private(set) var hasLoaded = false
    private(set) var plan = PlanDaysFile()
    private(set) var votes: [String: CardVote] = [:]
    private(set) var saved: [SavedAnswer] = []
    var planStatus: String?

    /// Set by AppModel: whether trial mode is on, and what to do when plan days change.
    var trialMode: () -> Bool = { true }
    var onPlanChange: () -> Void = {}
    /// Called once for each issue newer than any seen before (not on the very first load).
    var onNewIssue: (ReportIssue, String?) -> Void = { _, _ in }
    private static let lastIssueKey = "lastIssueSeen"

    init(folder: HealthGlanceFolder) { self.folder = folder }

    var latest: ReportIssue? { archive.issues.first.flatMap { issues[$0.date] } }
    var livePlanPath: String { "health/plan_days.csv" }
    var planPath: String { trialMode() ? "health_app/plan_days.csv" : livePlanPath }

    static func now() -> String { ISO8601DateFormatter().string(from: Date()) }

    // MARK: loading

    func reload() async {
        guard let root = folder.url else { return }
        if loading { loadAgain = true; return }
        loading = true
        defer { loading = false }
        repeat {
            loadAgain = false
            let known = cache, trial = trialMode(), live = livePlanPath, appPlan = planPath
            let folders = [("", "newsletter/issues")] + otherFolders().map { ($0.key, $0.value) }
            let loaded = await Task.detached(priority: .userInitiated) { () -> Loaded in
                let reader = FolderReader(root: root)
                var out = Loaded()
                for (section, folder) in folders {
                    for file in reader.list(folder) where file.name.hasSuffix(".json") {
                        let key = folder + "/" + file.name
                        if let hit = known[key], hit.modified == file.modified { out.cache[key] = hit; out.sections[key] = section; continue }
                        if let data = try? reader.read(key), let issue = try? ReportIssue.decode(data) {
                            out.cache[key] = (file.modified, issue); out.sections[key] = section
                        }
                    }
                }
                out.plan = PlanDaysFile(text: reader.text(live) ?? "")
                if trial, let text = reader.text(appPlan) { out.plan.merge(PlanDaysFile(text: text)) }
                if let data = try? reader.read(AppFiles.feedback) {
                    out.votes = (try? JSONDecoder().decode([String: CardVote].self, from: data)) ?? [:]
                }
                if let data = try? reader.read(AppFiles.saved) {
                    out.saved = (try? JSONDecoder().decode([SavedAnswer].self, from: data)) ?? []
                }
                return out
            }.value
            cache = loaded.cache
            func dated(_ section: String) -> [String: ReportIssue] {
                let all = loaded.cache.filter { loaded.sections[$0.key] == section }.values.map(\.issue)
                return Dictionary(all.map { ($0.date, $0) }) { a, _ in a }
            }
            let byDate = dated("")
            if byDate != issues { issues = byDate; archive = ReportArchive(issues: Array(byDate.values)) }
            var rest: [String: Edition] = [:]
            for (section, _) in folders where !section.isEmpty {
                let found = dated(section)
                if !found.isEmpty { rest[section] = Edition(issues: found, archive: ReportArchive(issues: Array(found.values))) }
            }
            if rest != others { others = rest }
            // A newer issue than any seen before, per section (never on the very first load).
            for (section, newest) in [("", latest)] + rest.map({ ($0.key, $0.value.latest) }) {
                guard let newest else { continue }
                let key = section.isEmpty ? Self.lastIssueKey : Self.lastIssueKey + "." + section
                let seen = UserDefaults.standard.string(forKey: key)
                if newest.date != seen { UserDefaults.standard.set(newest.date, forKey: key) }
                if let seen, newest.date > seen { onNewIssue(newest, section.isEmpty ? nil : section) }
            }
            if loaded.votes != votes { votes = loaded.votes }
            if loaded.saved != saved { saved = loaded.saved }
            if loaded.plan != plan { plan = loaded.plan; onPlanChange() }
            hasLoaded = true
        } while loadAgain
        writeStatus()
    }

    private struct Loaded: Sendable {
        var cache: [String: (modified: Date, issue: ReportIssue)] = [:]
        /// cache key → section key ("" = Health)
        var sections: [String: String] = [:]
        var plan = PlanDaysFile()
        var votes: [String: CardVote] = [:]
        var saved: [SavedAnswer] = []
    }

    /// Tells the morning run whether the app is on trial or owns the live files.
    func writeStatus() {
        guard folder.isLinked else { return }
        let trial = trialMode()
        if let data = try? folder.read(AppFiles.status),
           let old = try? JSONDecoder().decode(AppStatusFile.self, from: data),
           old.trial_mode == trial, old.plan_days == planPath { return }
        _ = try? folder.write(AppFiles.json(AppStatusFile(trialMode: trial, planDays: planPath, updated: Self.now())), to: AppFiles.status)
    }

    // MARK: food check-in

    func planCount(today: String) -> Int? { plan.count(today: today) }

    func savePlan(date: String, on: Bool, slips: [String], note: String) {
        let day = PlanDay(date: date, on: on, slips: slips, note: note.trimmingCharacters(in: .whitespacesAndNewlines), at: Self.now())
        do {
            // Read the target file fresh, replace that day, write the whole file back.
            var target = PlanDaysFile()
            if folder.exists(planPath), let text = String(data: try folder.read(planPath), encoding: .utf8) {
                target = PlanDaysFile(text: text)
            }
            target.save(day)
            try folder.write(target.text, to: planPath)
            plan.save(day)
            planStatus = trialMode() ? "Saved to the trial file. The morning run folds it into the dashboard."
                                     : "Saved. The Mac dashboard picks it up within a minute."
            onPlanChange()
        } catch {
            planStatus = "Couldn't save: \(error.localizedDescription)"
        }
    }

    // MARK: votes and kept answers

    func vote(for card: ReportCard, in issue: ReportIssue) -> Int {
        votes[CardVote.key(issueDate: issue.date, cardID: card.id)]?.vote ?? 0
    }

    /// Tapping the same thumb again clears it.
    func setVote(_ value: Int, for card: ReportCard, in issue: ReportIssue) {
        let key = CardVote.key(issueDate: issue.date, cardID: card.id)
        let previous = votes[key]
        let next = previous?.vote == value ? 0 : value
        votes[key] = CardVote(vote: next, issueDate: issue.date, card: card, section: issue.section(of: card), at: Self.now())
        do { try folder.write(AppFiles.json(votes), to: AppFiles.feedback) } catch { votes[key] = previous }
    }

    func keep(question: String, answer: String, card: ReportCard?, issue: ReportIssue) -> Bool {
        let entry = SavedAnswer(question: question, answer: answer, date: issue.date, card: card?.id ?? "plan-checkin",
                                pillar: card?.pillar ?? "Body", cardTitle: card.map { RichText.plain($0.title) } ?? "Your food plan",
                                section: card.map { issue.section(of: $0) } ?? SectionDefinition.healthKey, at: Self.now())
        saved.append(entry)
        do { try folder.write(AppFiles.json(saved), to: AppFiles.saved); return true } catch { saved.removeLast(); return false }
    }
}
