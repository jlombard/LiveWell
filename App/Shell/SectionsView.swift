import SwiftUI
import LiveWellCore

/// Sections: a card per section, then the library and data.
struct SectionsView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sections").font(Theme.serif(38, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader).padding(.bottom, 8)

                ForEach(model.config.sections) { section in
                    NavigationLink(value: Route.section(section.key)) { SectionCard(section: section) }.buttonStyle(.plain)
                }

                HStack(spacing: 12) {
                    Image(systemName: "plus").foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add a section").font(.subheadline).foregroundStyle(Theme.text.opacity(0.8))
                        Text(model.wealth.holdings.isEmpty ? "Wealth: import your holdings in Settings" : "Family is next")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    NavigationLink(value: Route.library) {
                        row("Library", "Kept answers, recipes and Labs")
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Button { showSettings = true } label: { row("Data and privacy", dataLine) }.buttonStyle(.plain)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// "Health synced 2 min ago · Mac built 10:53"
    private var dataLine: String {
        var parts: [String] = []
        if let last = model.lastSync {
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
            parts.append("Health synced \(f.localizedString(for: last, relativeTo: Date()))")
        } else {
            parts.append(model.health.hasRequested ? "Health not synced yet" : "Health not connected")
        }
        if let built = model.dashboard?.generated, let time = built.split(separator: "T").last { parts.append("Mac built \(time)") }
        if !model.folderLinked { parts = ["Folder not linked"] }
        return parts.joined(separator: " · ")
    }

    private func row(_ title: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// A section's card. Only the parts the section has are drawn: no goal, no countdown; no bars, no bars.
struct SectionCard: View {
    @Environment(AppModel.self) private var model
    let section: SectionDefinition

    private var isDashboard: Bool { section.key == model.config.dashboardSection?.key }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.name).font(.headline).foregroundStyle(Theme.text)
                Spacer()
                if let goal = section.goal, isDashboard {
                    Text(goal.title + (model.daysLeft.map { " · \($0) days" } ?? "")).font(.caption).foregroundStyle(Theme.secondary)
                } else if section.key == Wealth.sectionKey {
                    Text("Long lens").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            if isDashboard, let pillars = model.dashboard?.pillars, !pillars.isEmpty {
                VStack(spacing: 7) {
                    ForEach(pillars) { pillar in
                        HStack(spacing: 10) {
                            Text(pillar.label).font(.caption).foregroundStyle(Theme.secondary).frame(width: 64, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Theme.line)
                                    Rectangle().fill(Theme.accent).frame(width: geo.size.width * min(1, max(0, pillar.progress ?? 0)))
                                }
                            }
                            .frame(height: 2)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(pillar.label), \(Int(((pillar.progress ?? 0) * 100).rounded())) percent of the way")
                    }
                }
                .padding(.top, 14)
            }
            if section.key == Wealth.sectionKey {
                let rows = model.wealth.rows(today: model.today)
                HStack(spacing: 14) {
                    HStack(spacing: 7) { ForEach(rows) { StatusDot(status: $0.status) } }
                    Text(Wealth.next(rows)).font(.subheadline).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.top, 14)
                Text("Reasons written \(rows.filter { $0.status != .notWritten }.count) of \(rows.count)")
                    .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 8)
            }
            let parts = contents
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.secondary.opacity(0.8)).padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
    }

    /// "Dashboard · The Surf Report · Recipe box · Check-in", listing only what exists.
    private var contents: [String] {
        var parts: [String] = []
        if section.key == Wealth.sectionKey {
            return ["Why you own it"] + (model.report.others[section.key] == nil ? [] : [section.editionName ?? "Edition"]) + ["Ask"]
        }
        if section.dashboard { parts.append("Dashboard") }
        if let edition = section.editionName { parts.append(edition) }
        if isDashboard, !model.report.archive.recipes.isEmpty { parts.append("Recipe box") }
        if !section.measurements.isEmpty { parts.append("Check-in") }
        return parts
    }
}

/// On a section's home, under its dashboard: today's issue, its library and its rituals.
struct SectionLinks: View {
    @Environment(AppModel.self) private var model
    let section: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cover = model.editions.first(where: { $0.section == section }) {
                Eyebrow("Today\u{2019}s edition").padding(.bottom, 10)
                EditionCoverRow(cover: cover)
            }
            let due = model.rituals.filter { $0.section == section && $0.when == .dueNow }
            Rectangle().fill(Theme.line).frame(height: 1)
            NavigationLink(value: Route.checkin) {
                link("Check-in", due.first.map { "\($0.title) · \($0.detail)" } ?? "Measure, then commit to the week")
            }
            .buttonStyle(.plain)
            Rectangle().fill(Theme.line).frame(height: 1)
            NavigationLink(value: Route.library) { link("Library", "Kept answers, recipes and Labs") }.buttonStyle(.plain)
            Rectangle().fill(Theme.line).frame(height: 1)
            NavigationLink(value: Route.ask(section, nil)) { link("Ask", "A conversation about your \(model.config.sectionName(section).lowercased())") }.buttonStyle(.plain)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private func link(_ title: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Library: kept answers, recipes and Labs, searchable across sections.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var open: Set<String> = []

    private func matches(_ texts: String...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || texts.contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        let store = model.report
        let kept = store.saved.reversed().filter { matches($0.question, $0.answer, $0.cardTitle) }
        let recipes = store.archive.recipes.filter { matches(RichText.plain($0.card.title), $0.card.nutrient, ($0.card.recipe?.ingredients ?? []).joined(separator: " ")) }
        let labs = store.archive.issues.flatMap { entry in
            (store.issues[entry.date]?.contentCards ?? []).filter { $0.kind == "lab" }.map { (date: entry.date, card: $0) }
        }.filter { matches(RichText.plain($0.card.title), $0.card.label) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Library").font(Theme.serif(38, relativeTo: .largeTitle)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                TextField("Search", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    .padding(.top, 14)

                if kept.isEmpty && recipes.isEmpty && labs.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet. Answers you keep in Go deeper, recipes and Lab lessons collect here."
                                       : "Nothing matches \u{201C}\(query)\u{201D}.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 20)
                }
                if !kept.isEmpty {
                    Eyebrow("Kept answers · \(kept.count)").padding(.top, 24).padding(.bottom, 4)
                    ForEach(kept) { item in
                        entry(id: item.id, title: item.question, meta: shortDay(item.date)) {
                            Text(item.answer).font(.subheadline).foregroundStyle(Theme.text).textSelection(.enabled)
                            if !item.cardTitle.isEmpty { Text("From: \(item.cardTitle)").font(.caption).foregroundStyle(Theme.secondary) }
                        }
                    }
                }
                if !recipes.isEmpty {
                    Eyebrow("Recipes · \(recipes.count)").padding(.top, 24).padding(.bottom, 4)
                    ForEach(recipes) { item in
                        entry(id: "r" + item.id, title: RichText.plain(item.card.title), meta: item.card.nutrient) {
                            if let recipe = item.card.recipe { RecipeParts(recipe: recipe, palette: .normal) }
                            if let text = item.card.recipe?.copyText {
                                ShareLink(item: text) { Label("Share recipe", systemImage: "square.and.arrow.up") }.buttonStyle(GhostButton(palette: .normal))
                            }
                        }
                    }
                }
                if !labs.isEmpty {
                    Eyebrow("Labs · \(labs.count)").padding(.top, 24).padding(.bottom, 4)
                    ForEach(labs, id: \.card.id) { item in
                        entry(id: "l" + item.date + item.card.id, title: RichText.plain(item.card.title), meta: item.card.label) {
                            if let why = item.card.why { Rich(why, font: .subheadline) }
                            ForEach(Array(item.card.body.enumerated()), id: \.offset) { _, paragraph in Rich(paragraph, font: .subheadline) }
                            if let source = item.card.source { SourceLine(source: source, palette: .normal) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .task { await model.report.reload() }
    }

    private func entry<Content: View>(id: String, title: String, meta: String, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = open.contains(id)
        return VStack(alignment: .leading, spacing: 0) {
            Button { if isOpen { open.remove(id) } else { open.insert(id) } } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(Theme.serif(20, relativeTo: .title3)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(meta).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).padding(.bottom, 10)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}
