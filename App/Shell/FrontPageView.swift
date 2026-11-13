import SwiftUI
import LiveWellCore

/// Today, the front page: the date as masthead, a goals card with one row per section that has
/// something worth a glance, then today's editions as covers. The shell's own words stay neutral;
/// each section keeps its voice inside its own screens.
struct FrontPageView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    private var masthead: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Eyebrow("LiveWell")
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Theme.secondary).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings and data")
                }
                .frame(minHeight: 28)
                Text(masthead).font(Theme.serif(36, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)

                if !model.folderLinked {
                    setupCard("Link your Health Glance folder", "So the app can read your editions and progress, and write your data for the Mac.") { showSettings = true }
                } else if !model.health.hasRequested {
                    setupCard("Connect Apple Health", "Workouts sync on their own, with no Shortcuts.") { Task { await model.connectHealth() } }
                }

                goals.padding(.top, 16)

                let covers = model.editions
                if !covers.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow("Today\u{2019}s editions")
                        Spacer()
                        if let time = model.readingTime { Text(time).font(.caption).foregroundStyle(Theme.secondary) }
                    }
                    .padding(.top, 24).padding(.bottom, 10)
                    ForEach(covers) { cover in EditionCoverRow(cover: cover) }
                }

                // An occasional extra: this week's puzzle, until it has been played.
                if let extra = model.puzzleExtra {
                    NavigationLink(value: Route.issue(extra.section)) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.3x1.below.line.grid.1x2").font(.title3).foregroundStyle(Theme.accent).frame(width: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(extra.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text(extra.detail).font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .refreshable { await model.sync() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// One row per section with a state worth glancing at. A section with nothing to show is absent.
    @ViewBuilder private var goals: some View {
        let health = model.config.dashboardSection.flatMap { s in !model.statuses.isEmpty || s.goal != nil ? s : nil }
        let hasWealth = !model.wealth.holdings.isEmpty
        if health != nil || hasWealth {
            VStack(spacing: 0) {
                if let section = health {
                    NavigationLink(value: Route.section(section.key)) { healthRow(section) }.buttonStyle(.plain)
                        .accessibilityHint("Opens \(section.name)")
                }
                if health != nil && hasWealth { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 14) }
                if hasWealth {
                    NavigationLink(value: Route.section(Wealth.sectionKey)) { wealthRow }.buttonStyle(.plain)
                        .accessibilityHint("Opens Wealth")
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func healthRow(_ section: SectionDefinition) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(section.goal.map { goal in goal.title + (model.daysLeft.map { " · \($0) days" } ?? "") } ?? section.name)
                Text(model.todayLine).font(Theme.serif(21, relativeTo: .title3)).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                ForEach(model.statuses.filter { !$0.isOff }) { status in
                    Image(systemName: status.symbol ?? HabitSymbol.name(status.key))
                        .font(.system(size: 14, weight: status.met ? .bold : .regular))
                        .foregroundStyle(status.met ? Theme.accent : Theme.text)
                        .opacity(status.met ? 1 : 0.35)
                        .accessibilityLabel("\(status.name), \(status.met ? "met" : "not yet met")")
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// "WEALTH · NEXT: CHECK ASML" over "+2.1% IRA this week", with a dot per holding.
    private var wealthRow: some View {
        let rows = model.wealth.rows(today: model.today)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow("Wealth · " + Wealth.next(rows).replacingOccurrences(of: ".", with: ""))
                if let number = model.wealthNumber {
                    (Text(number.text).font(Theme.serif(21, relativeTo: .title3)).foregroundColor(Theme.text)
                     + Text(" " + (number.label == "this week" ? "IRA this week" : number.label)).font(.footnote).foregroundColor(Theme.secondary))
                } else {
                    Text("\(rows.count) holdings").font(Theme.serif(21, relativeTo: .title3)).foregroundStyle(Theme.text)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) { ForEach(rows) { StatusDot(status: $0.status, size: 11) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rows.map { "\($0.name) \($0.status.pill.lowercased())" }.joined(separator: ", "))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func setupCard(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Text(detail).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }
}

/// One edition's cover: section, edition name, story count, unread dot, lead headline.
struct EditionCoverRow: View {
    let cover: EditionCover

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            if cover.stories > 0 {
                NavigationLink(value: Route.issue(cover.section)) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(cover.sectionName).fontWeight(.semibold).foregroundStyle(Theme.text)
                Text("· \(cover.edition)" + (cover.stories > 0 ? " · \(cover.stories) \(cover.stories == 1 ? "story" : "stories")" : ""))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if cover.unread && cover.delayed == nil {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityLabel("Unread")
                }
            }
            .font(.caption)
            if let delayed = cover.delayed {
                Text(delayed).font(.footnote).foregroundStyle(Theme.text)
            }
            if !cover.lead.isEmpty {
                Rich(cover.lead, font: Theme.serif(23, relativeTo: .title2), emphasis: Theme.serif(23, relativeTo: .title2, italic: true),
                     color: cover.delayed == nil ? Theme.text : Theme.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.top, 14).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
