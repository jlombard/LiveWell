import SwiftUI
import LiveWellCore

/// Report tab: The Surf Report. Today's issue, past issues and the recipe box, read from the
/// issue files the Mac's morning run writes into newsletter/issues.
struct ReportView: View {
    @Environment(AppModel.self) private var model
    @State private var section: Section = .today
    /// A past issue being read (nil = today's).
    @State private var backIssue: String?
    @State private var deeper: DeeperTarget?

    enum Section: String, CaseIterable { case today = "Today", archive = "Past issues", recipes = "Recipe box" }

    private var store: ReportStore { model.report }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HorizonHeader()
                    header.padding(.top, 20)
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 14)
                    .id("top")

                    Group {
                        switch section {
                        case .today: today
                        case .archive: ArchiveList(archive: store.archive, latest: store.latest?.date) { open($0) }
                        case .recipes: RecipeBox(archive: store.archive) { open($0) }
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .onChange(of: section) { if section != .today { backIssue = nil }; proxy.scrollTo("top", anchor: .top) }
            .onChange(of: backIssue) { proxy.scrollTo("top", anchor: .top) }
            #if DEBUG && targetEnvironment(simulator)
            // Simulator only: `-demoSection archive|recipes`, `-demoCard <card id>`, `-demoDeeper 1` jump straight there.
            .task {
                let d = UserDefaults.standard
                if let raw = d.string(forKey: "demoSection") { section = raw == "archive" ? .archive : .recipes }
                await store.reload()
                try? await Task.sleep(for: .seconds(1))
                if let card = d.string(forKey: "demoCard") { proxy.scrollTo(card, anchor: .top) }
                if d.bool(forKey: "demoDeeper"), let issue = store.latest { deeper = DeeperTarget(issue: issue, card: issue.cards.first) }
            }
            #endif
        }
        .background(Theme.bg)
        .refreshable { await store.reload() }
        .task { await store.reload() }
        .sheet(item: $deeper) { target in
            GoDeeperSheet(target: target).presentationDragIndicator(.visible)
        }
    }

    private func open(_ date: String) {
        backIssue = date == store.latest?.date ? nil : date
        section = .today
    }

    private var shown: ReportIssue? { backIssue.flatMap { store.issues[$0] } ?? store.latest }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text("The ") + Text("Surf").font(Theme.serif(40, relativeTo: .largeTitle, italic: true)) + Text(" Report"))
                .font(Theme.serif(40, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            if section == .today, let issue = shown {
                Text((issue.issue.map { "No. \($0) · " } ?? "") + DayMath.dateline(issue.date))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    @ViewBuilder private var today: some View {
        if !model.folderLinked {
            empty("Link your Health Glance folder in Settings (the gear on Today) and the Report appears here.")
        } else if let issue = shown {
            let isBack = issue.date != store.latest?.date
            VStack(alignment: .leading, spacing: 16) {
                if isBack {
                    HStack {
                        Text("Back issue · \(DayMath.weekdayName(issue.date)), \(shortDay(issue.date))")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("Back to today") { backIssue = nil }.font(.footnote.weight(.semibold))
                    }
                } else if issue.date != model.today {
                    Text("Today's issue hasn't arrived yet. This is \(DayMath.weekdayName(issue.date))'s.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
                if let intro = issue.intro, !intro.isEmpty {
                    Rich(intro, font: Theme.serif(22, relativeTo: .title3, italic: true), color: Theme.secondary)
                }
                if !isBack {
                    PlanCheckinCard(issue: issue) { deeper = DeeperTarget(issue: issue, card: nil) }
                }
                ForEach(issue.cards) { card in
                    CardView(card: card, issue: issue,
                             onDeeper: { deeper = DeeperTarget(issue: issue, card: card) },
                             onSection: { section = $0 })
                        .id(card.id)
                }
            }
        } else if !store.hasLoaded {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            empty("No issues found yet. They arrive in newsletter/issues in the Health Glance folder after the Mac's morning run. Pull down to check again.")
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 8)
    }
}

/// What the Go deeper sheet is about: one card, or the food plan when `card` is nil.
struct DeeperTarget: Identifiable {
    let issue: ReportIssue
    let card: ReportCard?
    var id: String { issue.date + "_" + (card?.id ?? "plan-checkin") }
}

// MARK: one card

struct CardView: View {
    @Environment(AppModel.self) private var model
    let card: ReportCard
    let issue: ReportIssue
    var onDeeper: () -> Void
    var onSection: (ReportView.Section) -> Void
    @State private var picked: Int?

    private var palette: CardPalette { card.win ? .win : .normal }
    private var isEnd: Bool { card.kind == "end" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker(label: card.label, pillar: card.pillar, tag: card.tag, palette: palette)
            if isEnd, let days = model.daysLeft {
                Text("\(days)").font(Theme.serif(84, relativeTo: .largeTitle)).foregroundStyle(palette.text)
            }
            if !card.title.isEmpty {
                Rich(card.title, font: Theme.serif(30, relativeTo: .title), emphasis: Theme.serif(30, relativeTo: .title, italic: true),
                     color: palette.text)
                    .accessibilityAddTraits(.isHeader)
            }
            if let why = card.why { Rich(why, font: .headline, color: palette.text, linkColor: palette.accent) }
            if let figure = card.figure { FigureView(figure: figure, palette: palette) }
            ForEach(Array(card.body.enumerated()), id: \.offset) { _, paragraph in
                Rich(paragraph, color: palette.text, linkColor: palette.accent)
            }
            if !card.bullets.isEmpty { BulletList(items: card.bullets, palette: palette) }
            if let figure = card.figureAfter { FigureView(figure: figure, palette: palette) }
            if let recipe = card.recipe { RecipeParts(recipe: recipe, palette: palette) }
            if let lesson = card.lesson { LessonBox(lesson: lesson, palette: palette) }
            if let quiz = card.quiz { quizView(quiz) }
            if let tryIt = card.tryIt { TryBox(label: tryIt.label, text: tryIt.text, palette: palette) }
            if let sub = card.sub {
                Rich(sub, font: .footnote, color: palette.secondary, linkColor: palette.accent).textSelection(.enabled)
            }
            if let source = card.source { SourceLine(source: source, palette: palette) }
            if let text = card.recipe?.copyText {
                ShareLink(item: text) { Label("Share recipe", systemImage: "square.and.arrow.up") }
                    .buttonStyle(GhostButton(palette: palette))
            }
            if isEnd {
                HStack(spacing: 10) {
                    Button("Past issues") { onSection(.archive) }.buttonStyle(GhostButton(palette: palette))
                    Button("Recipe box") { onSection(.recipes) }.buttonStyle(GhostButton(palette: palette))
                }
            } else {
                tools
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var tools: some View {
        let vote = model.report.vote(for: card, in: issue)
        return HStack(spacing: 10) {
            Button(action: onDeeper) { Label("Go deeper", systemImage: "bubble.left") }
                .buttonStyle(GhostButton(palette: palette))
            Spacer()
            voteButton(1, pressed: vote == 1, symbol: "hand.thumbsup", label: "More like this")
            voteButton(-1, pressed: vote == -1, symbol: "hand.thumbsdown", label: "Less like this")
        }
        .padding(.top, 2)
    }

    private func voteButton(_ value: Int, pressed: Bool, symbol: String, label: String) -> some View {
        Button { model.report.setVote(value, for: card, in: issue) } label: {
            Image(systemName: pressed ? symbol + ".fill" : symbol)
                .foregroundStyle(pressed ? palette.accent : palette.secondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }

    private func quizView(_ quiz: ReportCard.Quiz) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(quiz.options.enumerated()), id: \.offset) { index, option in
                let revealed = picked != nil
                Button { if picked == nil { picked = index } } label: {
                    HStack {
                        Text(option.text).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer()
                        if revealed && option.right { Image(systemName: "checkmark").accessibilityLabel("Correct") }
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(revealed && option.right ? palette.accent.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(revealed && option.right ? palette.accent : palette.line, lineWidth: picked == index ? 2 : 1))
                    .foregroundStyle(palette.text)
                }
                .buttonStyle(.plain)
            }
            if picked != nil, !quiz.reveal.isEmpty { Rich(quiz.reveal, color: palette.text, linkColor: palette.accent).padding(.top, 4) }
        }
    }
}

struct Kicker: View {
    let label: String
    var pillar: String?
    var tag: String?
    let palette: CardPalette

    var body: some View {
        // One line when it fits; a long series kicker puts the pillar and tag on a second line.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { labelText; rest; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 6) {
                labelText
                HStack(spacing: 8) { rest; Spacer(minLength: 0) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(palette.text)
            .lineLimit(1).fixedSize()
    }

    @ViewBuilder private var rest: some View {
        if let pillar, !pillar.isEmpty {
            Text(pillar).font(.caption2.weight(.medium)).foregroundStyle(palette.text).lineLimit(1).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        }
        if let tag, !tag.isEmpty { Text(tag).font(.caption).foregroundStyle(palette.secondary).lineLimit(1).fixedSize() }
    }
}

struct BulletList: View {
    let items: [String]
    let palette: CardPalette
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("–").foregroundStyle(palette.secondary).accessibilityHidden(true)
                    Rich(item, color: palette.text, linkColor: palette.accent)
                }
            }
        }
    }
}

struct TryBox: View {
    let label: String
    let text: String
    let palette: CardPalette
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(palette.accent)
            Rich(text, font: .subheadline, color: palette.text, linkColor: palette.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line, lineWidth: 1))
    }
}

struct RecipeParts: View {
    let recipe: ReportCard.Recipe
    let palette: CardPalette
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            part("You need", recipe.ingredients, numbered: false)
            part("Do this", recipe.steps, numbered: true)
        }
        .textSelection(.enabled)
    }

    private func part(_ title: String, _ items: [String], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(palette.secondary)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(numbered ? "\(index + 1)." : "–").font(.subheadline.monospacedDigit()).foregroundStyle(palette.secondary)
                        .frame(minWidth: 18, alignment: .leading)
                    Text(item).font(.subheadline).foregroundStyle(palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct LessonBox: View {
    let lesson: ReportCard.Lesson
    let palette: CardPalette
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Kicker(label: "Nutrition lesson", tag: lesson.tag, palette: palette)
            ForEach(Array(lesson.body.enumerated()), id: \.offset) { _, paragraph in
                Rich(paragraph, font: .subheadline, color: palette.text, linkColor: palette.accent)
            }
            if let source = lesson.source { SourceLine(source: source, palette: palette) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.text.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct GhostButton: ButtonStyle {
    let palette: CardPalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Capsule())
    }
}

// MARK: food check-in

/// "How did yesterday go?" On plan or off plan, what got in the way, a note, and the last 7 days.
struct PlanCheckinCard: View {
    @Environment(AppModel.self) private var model
    let issue: ReportIssue
    var onDeeper: () -> Void
    @State private var day = ""
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private var store: ReportStore { model.report }
    private var today: String { model.today }
    private var choices: [(day: String, title: String, name: String)] {
        let yesterday = DayMath.adding(-1, to: today) ?? today, before = DayMath.adding(-2, to: today) ?? today
        return [(yesterday, "Yesterday", "yesterday"),
                (before, String(DayMath.weekdayName(before).prefix(3)), DayMath.weekdayName(before)),
                (today, "Today", "today")]
    }
    private var current: PlanDay? { store.plan[day] }
    private var goal: Int { issue.planGoal ?? Int(model.config.habit("plan")?.goal ?? 5) }

    var body: some View {
        let palette = CardPalette.normal
        VStack(alignment: .leading, spacing: 14) {
            Kicker(label: "Plan check-in", pillar: "Body", palette: palette)
            (Text("How did ") + Text(choices.first { $0.day == day }?.name ?? "that day").font(Theme.serif(30, relativeTo: .title, italic: true))
             + Text(" go?"))
                .font(Theme.serif(30, relativeTo: .title)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                ForEach(choices, id: \.day) { choice in
                    Chip(title: choice.title, selected: choice.day == day) { commitNote(); day = choice.day }
                }
            }
            Text("On plan: " + (issue.planDefinition ?? "measured nuts (or fruit instead), sensible dinner portions, office lunch from your go-to list."))
                .font(.footnote).foregroundStyle(Theme.secondary)

            HStack(spacing: 8) {
                Chip(title: "On plan", selected: current?.on == true) { save(on: true, slips: []) }
                Chip(title: "Off plan", selected: current?.on == false) { save(on: false, slips: current?.slips ?? []) }
            }

            if current?.on == false {
                Text("What got in the way? Optional, it shapes your tips.").font(.footnote).foregroundStyle(Theme.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(PlanDaysFile.slipChoices, id: \.self) { slip in
                        let on = current?.slips.contains(slip) ?? false
                        Chip(title: slip, selected: on) {
                            var slips = current?.slips ?? []
                            if on { slips.removeAll { $0 == slip } } else { slips.append(slip) }
                            save(on: false, slips: slips)
                        }
                    }
                }
            }

            TextField("Anything else? (optional)", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .focused($noteFocused)
                .submitLabel(.done)
                .padding(12)
                .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                .onChange(of: note) { if note.contains("\n") { note = note.replacingOccurrences(of: "\n", with: " "); noteFocused = false } }
                .onChange(of: noteFocused) { if !noteFocused { commitNote() } }

            if let status = store.planStatus { Text(status).font(.footnote).foregroundStyle(Theme.secondary) }

            week

            if let plate = issue.plate { TryBox(label: plate.label, text: plate.text, palette: palette) }

            Button(action: onDeeper) { Label("Go deeper", systemImage: "bubble.left") }.buttonStyle(GhostButton(palette: palette))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .onAppear { if day.isEmpty { day = choices[0].day }; note = current?.note ?? "" }
        .onChange(of: day) { note = current?.note ?? ""; store.planStatus = nil }
    }

    private var week: some View {
        let days = store.plan.lastSevenDays(before: today)
        let count = days.filter { store.plan[$0]?.on == true }.count
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Last 7 days")
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let entry = store.plan[d]
                    Text(String(DayMath.weekdayName(d).prefix(1)))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(entry?.on == true ? Theme.bg : (entry == nil ? Theme.secondary : Theme.text))
                        .background(entry?.on == true ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(entry == nil ? Theme.line : (entry?.on == true ? Color.clear : Theme.text),
                                    style: StrokeStyle(lineWidth: 1, dash: entry == nil ? [3, 3] : [])))
                        .accessibilityLabel("\(DayMath.weekdayName(d)): \(entry.map { $0.on ? "on plan" : "off plan" } ?? "not logged")")
                }
            }
            (Text("\(count)").fontWeight(.semibold) + Text(" of 7 on plan · goal ") + Text("\(goal)").fontWeight(.semibold))
                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
        }
    }

    private func save(on: Bool, slips: [String]) {
        store.savePlan(date: day, on: on, slips: slips, note: note)
    }

    private func commitNote() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (current?.note ?? "") else { return }
        guard let current else {
            if !trimmed.isEmpty { store.planStatus = "Pick On plan or Off plan first." }
            return
        }
        store.savePlan(date: day, on: current.on, slips: current.slips, note: trimmed)
    }
}

// MARK: past issues and recipe box

struct ArchiveList: View {
    let archive: ReportArchive
    let latest: String?
    var open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let n = archive.issues.count
            Text(n == 0 ? "No issues yet." : "\(n) \(n == 1 ? "issue" : "issues") so far. Tap one to read it again.")
                .font(.subheadline).foregroundStyle(Theme.secondary).padding(.bottom, 8)
            ForEach(archive.issues) { entry in
                Button { open(entry.date) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((entry.issue.map { "No. \($0) · " } ?? "") + DayMath.dateline(entry.date))
                            .font(.caption).foregroundStyle(Theme.secondary)
                        Rich(entry.lead, font: Theme.serif(22, relativeTo: .title3), emphasis: Theme.serif(22, relativeTo: .title3, italic: true))
                            .multilineTextAlignment(.leading)
                        Text("\(entry.count) cards" + (entry.recipes > 0 ? " · \(entry.recipes) \(entry.recipes == 1 ? "recipe" : "recipes")" : "")
                             + (entry.date == latest ? " · latest" : ""))
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
    }
}

struct RecipeBox: View {
    let archive: ReportArchive
    var open: (String) -> Void
    @State private var expanded: Set<String> = []

    var body: some View {
        let palette = CardPalette.normal
        VStack(alignment: .leading, spacing: 0) {
            Text(archive.recipes.isEmpty ? "No recipes yet. They arrive with Kitchen cards."
                 : "Every recipe from The Surf Report, grouped by the nutrient it's richest in.")
                .font(.subheadline).foregroundStyle(Theme.secondary).padding(.bottom, 8)
            ForEach(archive.recipeGroups, id: \.nutrient) { group in
                Eyebrow("\(group.nutrient) · \(group.recipes.count)").padding(.top, 18).padding(.bottom, 4)
                ForEach(group.recipes) { entry in
                    let isOpen = expanded.contains(entry.id)
                    Button {
                        if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Rich(entry.card.title, font: Theme.serif(22, relativeTo: .title3), emphasis: Theme.serif(22, relativeTo: .title3, italic: true))
                                .multilineTextAlignment(.leading)
                            Text(shortDay(entry.date)).font(.caption).foregroundStyle(Theme.secondary)
                            Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Theme.secondary)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isOpen ? "Hides the recipe" : "Shows the recipe")
                    if isOpen {
                        VStack(alignment: .leading, spacing: 14) {
                            Kicker(label: "Kitchen", pillar: entry.card.pillar, tag: entry.card.tag, palette: palette)
                            if let why = entry.card.why { Rich(why, font: .headline) }
                            if let recipe = entry.card.recipe { RecipeParts(recipe: recipe, palette: palette) }
                            if let lesson = entry.card.lesson { LessonBox(lesson: lesson, palette: palette) }
                            HStack(spacing: 10) {
                                if let text = entry.card.recipe?.copyText {
                                    ShareLink(item: text) { Label("Share recipe", systemImage: "square.and.arrow.up") }
                                        .buttonStyle(GhostButton(palette: palette))
                                }
                                Button("Open the \(shortDay(entry.date)) issue") { open(entry.date) }.buttonStyle(GhostButton(palette: palette))
                            }
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.bottom, 10)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
        }
    }
}
