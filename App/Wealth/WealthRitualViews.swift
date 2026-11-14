import SwiftUI
import LiveWellCore

/// Three answers in a row, one chosen.
private struct Choice<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.value) { option in
                Chip(title: option.label, selected: selection == option.value) { selection = option.value; UISelectionFeedbackGenerator().selectionChanged() }
            }
        }
    }
}

private struct RitualShell<Content: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(kicker)
                Text(title).font(Theme.serif(34, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader).padding(.top, 6)
                content
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// The closing screen of a ritual: one line, then back to the reasons.
private struct RitualDone: View {
    @Environment(\.dismiss) private var dismiss
    let headline: String
    let line: String
    let belief: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline).font(Theme.serif(40, relativeTo: .largeTitle)).foregroundStyle(Theme.text).padding(.top, 30)
            Text(line).font(.body).foregroundStyle(Theme.text).padding(.top, 12)
            Rectangle().fill(Theme.accent).frame(width: 120, height: 1).padding(.top, 28)
            if let belief {
                Eyebrow("Why you own it").padding(.top, 20)
                Text(belief).font(Theme.serif(20, relativeTo: .title3, italic: true)).foregroundStyle(Theme.secondary).padding(.top, 8)
            }
            Button("Done") { dismiss() }.foregroundStyle(Theme.text).frame(minHeight: 44).padding(.top, 28)
        }
        .transition(.opacity)
    }
}

/// "What to watch", the day before a report: pick what matters this time and write what would
/// make him doubt, before the price has an opinion.
struct WatchView: View {
    @Environment(AppModel.self) private var model
    let ticker: String
    @State private var picked: Set<String> = []
    @State private var doubt = ""
    @State private var saved: WatchNote?

    var body: some View {
        let name = model.wealth.holding(ticker)?.displayName ?? ticker
        let reasons = model.wealth.reasons[ticker]
        let report = WealthRituals.next(model.wealth.earnings, ticker, today: model.today)
        RitualShell(kicker: "Wealth · before earnings", title: "What to watch: \(name)") {
            if let saved {
                RitualDone(headline: "Written.", line: "You\u{2019}ll see this again after the report, beside the \u{201C}Still true?\u{201D} check: \u{201C}\(saved.doubt)\u{201D}",
                           belief: reasons?.belief)
            } else {
                Text(report.map { "\(name) reports \(DayMath.weekdayName($0.date)), \(shortDay($0.date))\($0.when.map { " \($0)" } ?? ""). Two minutes now, before the number and the price reaction." }
                     ?? "No report date is known for \(name) yet. You can still write this down.")
                    .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 10)

                if let reasons, !reasons.watch.isEmpty {
                    Eyebrow("Your things to watch · pick what this report can speak to").padding(.top, 24).padding(.bottom, 8)
                    ForEach(reasons.watch, id: \.self) { item in pick(item) }
                    if !reasons.dealBreakers.isEmpty {
                        Eyebrow("Your deal-breakers").padding(.top, 22).padding(.bottom, 8)
                        BulletList(items: reasons.dealBreakers, palette: .normal)
                    }
                } else {
                    Eyebrow("The standing questions").padding(.top, 24).padding(.bottom, 8)
                    ForEach(["Did the main engine grow?", "Did margins hold, and what is the guidance?", "Cash flow, margins and debt: anything off?", "Is it the same story as last quarter?"], id: \.self) { pick($0) }
                    Text("You haven\u{2019}t written why you own \(name), so there are no things to watch of your own yet.")
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 10)
                }

                Text("What result would make you doubt \(name), as opposed to just disappoint you?")
                    .font(Theme.serif(22, relativeTo: .title3)).foregroundStyle(Theme.text).padding(.top, 26)
                TextField("One sentence", text: $doubt, axis: .vertical).lineLimit(2...5)
                    .padding(12).background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1)).padding(.top, 10)

                PrimaryButton(title: "Save") {
                    let note = WatchNote(ticker: ticker, earnings: report?.date ?? model.today, watching: reasons.map { r in r.watch.filter(picked.contains) } ?? Array(picked),
                                         doubt: doubt.trimmingCharacters(in: .whitespacesAndNewlines), written: model.today)
                    model.wealth.saveWatch(note)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.6)) { saved = note }
                }
                .disabled(doubt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(doubt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .padding(.top, 20)
                Text("Education and decision support, not buy or sell advice.").font(.caption2).foregroundStyle(Theme.secondary).padding(.top, 12)
            }
        }
        .onAppear {
            if let report, let existing = model.wealth.record.note(ticker, earnings: report.date) { picked = Set(existing.watching); doubt = existing.doubt }
        }
    }

    private func pick(_ item: String) -> some View {
        let on = picked.contains(item)
        return Button { if on { picked.remove(item) } else { picked.insert(item) } } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.accent : Theme.secondary)
                Text(item).font(.subheadline).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The "Still true?" check: each reason and each deal-breaker judged against the latest report.
struct StillTrueView: View {
    @Environment(AppModel.self) private var model
    let ticker: String
    @State private var reasons: [StillTrueCheck.ReasonState] = []
    @State private var breakers: [StillTrueCheck.BreakerState] = []
    @State private var note = ""
    @State private var saved: StillTrueCheck?

    var body: some View {
        let name = model.wealth.holding(ticker)?.displayName ?? ticker
        let written = model.wealth.reasons[ticker]
        let report = WealthRituals.last(model.wealth.earnings, ticker, today: model.today)
        RitualShell(kicker: "Wealth · \u{201C}Still true?\u{201D} check", title: name) {
            if let saved {
                RitualDone(headline: saved.outcome.status == .stillTrue ? "Still true." : (saved.outcome.status == .dealBreaker ? "Worth a hard look." : "One to check."),
                           line: saved.outcome.line + (saved.outcome.status == .dealBreaker ? " This is information, not an instruction: take it to Ask, and to your framework, before anything else." : ""),
                           belief: written?.belief)
            } else if let written {
                Text(written.belief).font(Theme.serif(20, relativeTo: .title3, italic: true)).foregroundStyle(Theme.secondary).padding(.top, 12)
                if let report {
                    Text("\(name) reported \(DayMath.weekdayName(report.date)), \(shortDay(report.date)). Judge each line against what the report and the call said, not against the price.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 12)
                }
                if let before = report.flatMap({ model.wealth.record.note(ticker, earnings: $0.date) }) ?? model.wealth.record.watch.last(where: { $0.ticker == ticker }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("What you wrote before the report")
                        Text("\u{201C}\(before.doubt)\u{201D}").font(.subheadline).foregroundStyle(Theme.text)
                        if !before.watching.isEmpty { Text("Watching: " + before.watching.joined(separator: " · ")).font(.footnote).foregroundStyle(Theme.secondary) }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).padding(.top, 16)
                }
                NavigationLink(value: Route.ask(Wealth.sectionKey, ticker)) {
                    Label("Ask to check the report against these", systemImage: "bubble.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButton(palette: .normal)).padding(.top, 16)

                Eyebrow("Reasons").padding(.top, 26)
                ForEach(Array(written.reasons.enumerated()), id: \.offset) { index, text in
                    Text(text).font(.subheadline).foregroundStyle(Theme.text).padding(.top, 14)
                    Choice(options: StillTrueCheck.ReasonState.allCases.map { ($0, $0.label) },
                           selection: Binding(get: { reasons.indices.contains(index) ? reasons[index] : .yes }, set: { if reasons.indices.contains(index) { reasons[index] = $0 } }))
                        .padding(.top, 8)
                }
                Eyebrow("Deal-breakers").padding(.top, 28)
                ForEach(Array(written.dealBreakers.enumerated()), id: \.offset) { index, text in
                    Text(text).font(.subheadline).foregroundStyle(Theme.text).padding(.top, 14)
                    Choice(options: StillTrueCheck.BreakerState.allCases.map { ($0, $0.label) },
                           selection: Binding(get: { breakers.indices.contains(index) ? breakers[index] : .clear }, set: { if breakers.indices.contains(index) { breakers[index] = $0 } }))
                        .padding(.top, 8)
                }
                TextField("A note on what you saw (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                    .padding(12).background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1)).padding(.top, 24)
                PrimaryButton(title: "Record the check") {
                    let check = StillTrueCheck(ticker: ticker, date: model.today, earnings: report?.date,
                                               reasons: zip(written.reasons, reasons).map { .init(text: $0, state: $1) },
                                               dealBreakers: zip(written.dealBreakers, breakers).map { .init(text: $0, state: $1) },
                                               note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                    model.wealth.saveCheck(check)
                    UINotificationFeedbackGenerator().notificationOccurred(check.outcome.status == .stillTrue ? .success : .warning)
                    withAnimation(.easeInOut(duration: 0.6)) { saved = check }
                }
                .padding(.top, 20)
            } else {
                Text("You haven\u{2019}t written why you own \(name), so there is nothing to check it against yet.")
                    .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 12)
                NavigationLink(value: Route.ask(Wealth.sectionKey, ticker)) {
                    Text("Write it").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.text, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Theme.bg)
                }
                .buttonStyle(.plain).padding(.top, 18)
            }
        }
        .onAppear {
            guard reasons.isEmpty, let written = model.wealth.reasons[ticker] else { return }
            // Start from "still true" and "not hit"; he changes what the report changed.
            reasons = Array(repeating: .yes, count: written.reasons.count)
            breakers = Array(repeating: .clear, count: written.dealBreakers.count)
        }
    }
}

/// The leadership check: the framework's three values filters, asked again after a change at the top.
struct ValuesCheckView: View {
    @Environment(AppModel.self) private var model
    let ticker: String
    @State private var answers: [ValuesCheck.Answer] = [.yes, .yes, .unsure]
    @State private var note = ""
    @State private var saved: ValuesCheck?

    var body: some View {
        let name = model.wealth.holding(ticker)?.displayName ?? ticker
        RitualShell(kicker: "Wealth · leadership check", title: name) {
            if let saved {
                RitualDone(headline: saved.answers.allSatisfy { $0 == .yes } ? "They hold." : "Noted.", line: saved.line, belief: model.wealth.reasons[ticker]?.belief)
            } else {
                Text("Your framework asks these of every company before anything else, and again when the person at the wheel changes. Answer from what you have seen, not from the headlines.")
                    .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 10)
                ForEach(Array(ValuesCheck.questions.enumerated()), id: \.offset) { index, question in
                    Eyebrow(question.title).padding(.top, 24)
                    Text(question.asks).font(Theme.serif(20, relativeTo: .title3)).foregroundStyle(Theme.text).padding(.top, 6)
                    Choice(options: ValuesCheck.Answer.allCases.map { ($0, $0.label) },
                           selection: Binding(get: { answers[index] }, set: { answers[index] = $0 })).padding(.top, 10)
                }
                NavigationLink(value: Route.ask(Wealth.sectionKey, ticker)) {
                    Label("Ask what the new leadership has said and done", systemImage: "bubble.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButton(palette: .normal)).padding(.top, 22)
                TextField("What makes you say that? (optional)", text: $note, axis: .vertical).lineLimit(1...4)
                    .padding(12).background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1)).padding(.top, 16)
                PrimaryButton(title: "Record the check") {
                    let check = ValuesCheck(ticker: ticker, date: model.today, trigger: "Change at the top", customer: answers[0], world: answers[1],
                                            leadership: answers[2], note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                    model.wealth.saveValues(check)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.6)) { saved = check }
                }
                .padding(.top, 20)
            }
        }
    }
}
