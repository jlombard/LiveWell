import SwiftUI
import LiveWellCore

/// One holding: his reasons as written, or the way to write them.
struct HoldingView: View {
    @Environment(AppModel.self) private var model
    let ticker: String

    var body: some View {
        let holding = model.wealth.holding(ticker)
        let row = model.wealth.rows(today: model.today).first { $0.ticker == ticker }
        let reasons = model.wealth.reasons[ticker]
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Wealth · \(ticker)" + (row?.share.map { " · \(Int(($0 * 100).rounded()))% of the account" } ?? ""))
                Text(holding?.displayName ?? ticker).font(Theme.serif(38, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader).padding(.top, 6)

                if let reasons {
                    Text(reasons.belief).font(Theme.serif(22, relativeTo: .title3)).foregroundStyle(Theme.text).padding(.top, 16)
                    list("Reasons", reasons.reasons)
                    list("Deal-breakers", reasons.dealBreakers)
                    list("Things to watch", reasons.watch)
                    Text(reasons.source == "framework" ? "From your investment framework." : "Written \(shortDay(reasons.written)).")
                        .font(.caption).foregroundStyle(Theme.secondary).padding(.top, 16)
                    NavigationLink(value: Route.ask(Wealth.sectionKey, ticker)) {
                        Label("Revise with Ask", systemImage: "bubble.left").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GhostButton(palette: .normal)).padding(.top, 14)
                } else {
                    Text("Not written yet.").font(Theme.serif(22, relativeTo: .title3)).foregroundStyle(Theme.text).padding(.top, 16)
                    Text("Your reasons for owning \(holding?.displayName ?? ticker) are what every story about it gets judged against. Ask walks you through nine lenses, grounded in the company\u{2019}s own filings. It proposes; you decide every line.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 8)
                    if let row, row.next != "Write why you own it" {
                        Text(row.next).font(.footnote).foregroundStyle(Theme.text).padding(.top, 10)
                    }
                    NavigationLink(value: Route.ask(Wealth.sectionKey, ticker)) {
                        Text(model.wealth.drafts[ticker] == nil ? "Write it" : "Continue")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                            .background(Theme.text, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Theme.bg)
                    }
                    .buttonStyle(.plain).padding(.top, 18)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
    }

    @ViewBuilder private func list(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            Eyebrow(title).padding(.top, 22).padding(.bottom, 8)
            BulletList(items: items, palette: .normal)
        }
    }
}

/// Ask: a conversation scoped to a section. With a holding, it is the guided way to write his
/// reasons: nine lenses, proposals he approves one line at a time, and a draft that builds beside it.
struct AskView: View {
    @Environment(AppModel.self) private var model
    let section: String
    let ticker: String?

    struct Message: Identifiable {
        enum Role { case reader, claude, note }
        let id = UUID()
        var role: Role
        var text: String
        var proposals: [Proposals.Proposal] = []
        var finished = false
    }

    @State private var messages: [Message] = []
    @State private var turns: [GoDeeper.Turn] = []
    @State private var input = ""
    @State private var asking: Task<Void, Never>?
    @State private var hasKey = Keychain.apiKey != nil
    @State private var lens: String?
    @State private var showDraft = false
    @FocusState private var inputFocused: Bool

    private var isWealth: Bool { section == Wealth.sectionKey }
    private var holding: Holding? { ticker.flatMap { model.wealth.holding($0) } }
    private var draft: ReasonsDraft? { ticker.map { model.wealth.draft($0) } }
    private var title: String { holding.map { "Why you own \($0.displayName)" } ?? "Ask \(model.config.sectionName(section))" }

    private var starters: [String] {
        if holding != nil { return [] }
        if isWealth { return ["What should I be watching across my holdings this quarter?", "Make the case against my largest holding", "Run the Supply chain lens on a company I\u{2019}m watching"] }
        return ["What should I focus on this week?", "Why does my progress look the way it does?", "What would move my slowest bar?"]
    }

    private var system: String {
        if isWealth {
            let rows = model.wealth.rows(today: model.today)
            return Ask.wealthSystem(
                holdings: rows.map { ($0.name, $0.ticker, $0.share.map { Int(($0 * 100).rounded()) }, $0.status != .notWritten) },
                today: model.today, focus: holding.map { ($0.displayName, $0.ticker) }, lens: lens.flatMap(Lens.named),
                draft: draft, existing: ticker.flatMap { model.wealth.reasons[$0] })
        }
        return Ask.healthSystem(profile: model.report.latest?.profile ?? "", today: model.today)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Ask · \(model.config.sectionName(section))")
                Text(title).font(Theme.serif(28, relativeTo: .title)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)

            if holding != nil { lenses.padding(.top, 12) }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !hasKey {
                            note("Ask talks to Claude from this phone, so it needs your Anthropic API key. Add it in Settings (the gear on Today), under Go deeper chat.")
                        } else if messages.isEmpty {
                            if let holding {
                                note("Nine lenses, one at a time, each grounded in \(holding.displayName)\u{2019}s own filings. Pick a lens above to begin. Claude proposes lines; a line is yours only when you add it to the draft.")
                            } else {
                                note("Ask anything about your \(model.config.sectionName(section).lowercased()), or start with one of these:")
                                ForEach(starters, id: \.self) { question in
                                    Button { ask(question) } label: {
                                        Text(question).font(.subheadline).multilineTextAlignment(.leading)
                                            .padding(.horizontal, 14).padding(.vertical, 12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                                            .foregroundStyle(Theme.text)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach(messages) { bubble($0) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .onChange(of: messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: messages.count) { proxy.scrollTo("end", anchor: .bottom) }
            }

            if hasKey {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(holding == nil ? "Ask\u{2026}" : "Your answer, or a question\u{2026}", text: $input, axis: .vertical)
                        .lineLimit(1...4).focused($inputFocused)
                        .padding(12)
                        .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                    Button(asking == nil ? "Send" : "Stop") { if let asking { asking.cancel() } else { ask(input) } }
                        .font(.headline).frame(minWidth: 64, minHeight: 46)
                        .background(Theme.text, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Theme.bg)
                        .disabled(asking == nil && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let draft {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Draft · \(draft.lines.count)") { showDraft = true }.font(.subheadline.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showDraft) { if let ticker { DraftSheet(ticker: ticker).presentationDragIndicator(.visible) } }
        .onDisappear { asking?.cancel() }
    }

    /// The nine lenses: tap to start one, and it is marked done when you move on.
    private var lenses: some View {
        let done = Set(draft?.lensesDone ?? [])
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Lens.all) { item in
                    let current = lens == item.key
                    Button { start(item) } label: {
                        HStack(spacing: 5) {
                            if done.contains(item.key) { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                            Text(item.name).font(.footnote.weight(current ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(current ? Theme.accent.opacity(0.16) : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(current ? Theme.accent : Theme.line, lineWidth: 1))
                        .foregroundStyle(done.contains(item.key) && !current ? Theme.secondary : Theme.text)
                    }
                    .buttonStyle(.plain)
                    .disabled(asking != nil || !hasKey)
                    .accessibilityLabel("\(item.name) lens\(done.contains(item.key) ? ", done" : "")\(current ? ", current" : "")")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func note(_ text: String) -> some View { Text(text).font(.footnote).foregroundStyle(Theme.secondary) }

    @ViewBuilder private func bubble(_ m: Message) -> some View {
        switch m.role {
        case .note: note(m.text)
        case .reader:
            Text(m.text).font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .claude:
            VStack(alignment: .leading, spacing: 10) {
                Text(m.text.isEmpty ? (isWealth ? "Reading the filings\u{2026}" : "Thinking\u{2026}") : m.text)
                    .font(.body).foregroundStyle(m.text.isEmpty ? Theme.secondary : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                if m.finished { ForEach(m.proposals) { proposalCard($0) } }
            }
        }
    }

    /// A proposed line. It joins the draft only when he taps Add.
    private func proposalCard(_ p: Proposals.Proposal) -> some View {
        let added = draft?.lines.contains { $0.kind == p.kind && $0.text == p.text } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Proposed · " + (p.kind == .belief ? "I believe" : String(p.kind.heading.dropLast(p.kind == .watch ? 0 : 1))))
            Text(p.text).font(.subheadline).foregroundStyle(Theme.text)
            Button(added ? "In your draft" : "Add to my draft") {
                guard let ticker else { return }
                var d = model.wealth.draft(ticker)
                d.approve(p.kind, p.text, lens: lens, id: UUID().uuidString)
                model.wealth.setDraft(d)
            }
            .buttonStyle(GhostButton(palette: .normal)).disabled(added)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: added ? [] : [4, 4])))
    }

    /// Starting a lens marks the one before it done.
    private func start(_ item: Lens) {
        guard let ticker, let holding else { return }
        var d = model.wealth.draft(ticker)
        if let previous = lens, previous != item.key, !d.lensesDone.contains(previous), messages.contains(where: { $0.role == .claude && $0.finished }) {
            d.lensesDone.append(previous)
        }
        model.wealth.setDraft(d)
        lens = item.key
        ask("Let\u{2019}s look at \(holding.displayName) through the \(item.name) lens.")
    }

    private func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, asking == nil else { return }
        input = ""
        messages.append(Message(role: .reader, text: question))
        turns.append(GoDeeper.Turn(fromReader: true, text: question))
        messages.append(Message(role: .claude, text: ""))
        let answerID = messages[messages.count - 1].id
        let prompt = system, history = turns, chosen = model.settings.chatModel, search = isWealth

        asking = Task { @MainActor in
            defer { asking = nil }
            @MainActor func update(_ change: (inout Message) -> Void) {
                if let i = messages.firstIndex(where: { $0.id == answerID }) { change(&messages[i]) }
            }
            do {
                let answer = try await ClaudeClient.ask(model: chosen, system: prompt, turns: history, webSearch: search) { soFar in
                    update { $0.text = Proposals.split(soFar).text }
                }
                let parts = Proposals.split(answer.text)
                update { $0.text = parts.text; $0.proposals = parts.proposals; $0.finished = true }
                turns.append(GoDeeper.Turn(fromReader: false, text: answer.text))
                if answer.truncated { messages.append(Message(role: .note, text: "That answer stopped part-way. Ask it to continue.")) }
            } catch {
                let partial = messages.first { $0.id == answerID }?.text ?? ""
                if partial.isEmpty { messages.removeAll { $0.id == answerID }; turns.removeLast() }
                else { update { $0.finished = true }; turns.append(GoDeeper.Turn(fromReader: false, text: partial)) }
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled {
                    messages.append(Message(role: .note, text: (error as? LocalizedError)?.errorDescription ?? "Something interrupted the answer. Ask again."))
                }
            }
        }
    }
}

/// The draft beside the conversation: every line is his, and he can reword or remove any of them.
struct DraftSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ticker: String
    @State private var adding: ReasonsDraft.Kind?
    @State private var newLine = ""

    var body: some View {
        let draft = model.wealth.draft(ticker)
        let name = model.wealth.holding(ticker)?.displayName ?? ticker
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Your draft · \(draft.lensesDone.count) of \(Lens.all.count) lenses done")
                Text("Why you own \(name)").font(Theme.serif(30, relativeTo: .title)).foregroundStyle(Theme.text).padding(.top, 6)

                ForEach(ReasonsDraft.Kind.allCases, id: \.self) { kind in
                    HStack {
                        Eyebrow(kind.heading)
                        Spacer()
                        Button("Add your own") { adding = kind; newLine = kind == .belief ? "I believe \(name) will keep winning because " : "" }
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    .padding(.top, 22).padding(.bottom, 6)
                    if draft.lines(kind).isEmpty { Text("Nothing yet.").font(.footnote).foregroundStyle(Theme.secondary) }
                    ForEach(draft.lines(kind)) { line in DraftLineRow(ticker: ticker, line: line) }
                    if adding == kind {
                        TextField("Your words", text: $newLine, axis: .vertical).lineLimit(1...4)
                            .padding(12).background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)).padding(.top, 6)
                        Button("Add") {
                            var d = model.wealth.draft(ticker); d.approve(kind, newLine, lens: nil, id: UUID().uuidString)
                            model.wealth.setDraft(d); adding = nil; newLine = ""
                        }
                        .buttonStyle(GhostButton(palette: .normal)).padding(.top, 8)
                    }
                }

                if let missing = draft.missing {
                    Text(missing).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 24)
                } else {
                    PrimaryButton(title: model.wealth.reasons[ticker] == nil ? "Save as my reasons" : "Save the changes") {
                        if model.wealth.saveReasons(ticker, today: model.today) { dismiss() }
                    }
                    .padding(.top, 24)
                    Text("Every story about \(name) will be judged against these, not against the price.")
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 10)
                }
            }
            .padding(24)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}

private struct DraftLineRow: View {
    @Environment(AppModel.self) private var model
    let ticker: String
    let line: ReasonsDraft.Line
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("", text: $text, axis: .vertical).lineLimit(1...6).font(.subheadline).foregroundStyle(Theme.text).focused($focused)
                .onAppear { text = line.text }
                .onChange(of: focused) { if !focused { commit() } }
            Button { remove() } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(Theme.secondary).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Remove this line")
        }
        .padding(.leading, 12).padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }

    private func commit() {
        var d = model.wealth.draft(ticker)
        guard let i = d.lines.firstIndex(where: { $0.id == line.id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { d.lines.remove(at: i) } else if d.lines[i].text != clean { d.lines[i].text = clean } else { return }
        model.wealth.setDraft(d)
    }

    private func remove() {
        var d = model.wealth.draft(ticker)
        d.lines.removeAll { $0.id == line.id }
        model.wealth.setDraft(d)
    }
}
