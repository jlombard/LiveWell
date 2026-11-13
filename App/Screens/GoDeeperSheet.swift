import SwiftUI
import LiveWellCore

/// Go deeper: ask Claude about one card (or the food plan). Starter questions, a streamed
/// answer, and "Keep this" to save an answer where the morning run can read it.
struct GoDeeperSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: DeeperTarget

    struct Message: Identifiable {
        enum Role { case reader, claude, note }
        let id = UUID()
        var role: Role
        var text: String
        /// The question this answer replied to (set on finished answers, for "Keep this").
        var question: String?
        var kept = false
    }

    @State private var messages: [Message] = []
    @State private var turns: [GoDeeper.Turn] = []
    @State private var draft = ""
    @State private var asking: Task<Void, Never>?
    @State private var hasKey = Keychain.apiKey != nil
    @FocusState private var inputFocused: Bool

    private var title: String { target.card.map { RichText.plain($0.title) } ?? "Your food plan" }
    private var tagLine: String {
        (target.card.map { [$0.pillar, $0.tag] } ?? ["Body", "Food plan"]).compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var starters: [String] {
        if let card = target.card { return card.starters }
        return target.issue.planStarters.isEmpty ? GoDeeper.planStarters : target.issue.planStarters
    }

    /// The card as Claude sees it. The food plan card adds the logged days.
    private var cardText: String {
        if let card = target.card { return card.plainText }
        let issue = target.issue
        return "Food plan check-in card. " + model.report.plan.summary(
            definition: issue.planDefinition ?? "", goal: issue.planGoal ?? 5, today: model.today, plate: issue.plate?.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("GO DEEPER").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Theme.text)
                        Text(tagLine).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Text(title).font(Theme.serif(24, relativeTo: .title2)).foregroundStyle(Theme.text).lineLimit(3)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.secondary).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20).padding(.top, 22)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !hasKey {
                            note("Go deeper asks Claude from this phone, so it needs your Anthropic API key. Add it in Settings (the gear on Today), under Go deeper chat.")
                        } else if messages.isEmpty {
                            note("Ask a question about this card, or start with one of these:")
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
                        ForEach($messages) { $message in bubble($message) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .onChange(of: messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: messages.count) { proxy.scrollTo("end", anchor: .bottom) }
            }

            if hasKey {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask anything about this card…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .padding(12)
                        .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                    Button(asking == nil ? "Ask" : "Stop") {
                        if let asking { asking.cancel() } else { ask(draft) }
                    }
                    .font(.headline)
                    .frame(minWidth: 64, minHeight: 46)
                    .background(Theme.text, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.bg)
                    .disabled(asking == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .background(Theme.bg)
        .onDisappear { asking?.cancel() }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Theme.secondary)
    }

    @ViewBuilder private func bubble(_ message: Binding<Message>) -> some View {
        let m = message.wrappedValue
        switch m.role {
        case .note: note(m.text)
        case .reader:
            Text(m.text).font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .claude:
            VStack(alignment: .leading, spacing: 10) {
                Text(m.text.isEmpty ? "Thinking…" : m.text)
                    .font(.body).foregroundStyle(m.text.isEmpty ? Theme.secondary : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if let question = m.question {
                    Button(m.kept ? "Kept. It will shape future cards." : "Keep this in my field guide") {
                        message.wrappedValue.kept = model.report.keep(question: question, answer: m.text, card: target.card, issue: target.issue)
                        if !message.wrappedValue.kept { messages.append(Message(role: .note, text: "Couldn't save. Try again.")) }
                    }
                    .buttonStyle(GhostButton(palette: .normal))
                    .disabled(m.kept)
                }
            }
        }
    }

    private func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, asking == nil else { return }
        draft = ""
        messages.append(Message(role: .reader, text: question))
        turns.append(GoDeeper.Turn(fromReader: true, text: question))
        messages.append(Message(role: .claude, text: ""))
        let answerID = messages[messages.count - 1].id
        let section = target.card.map { target.issue.section(of: $0) } ?? SectionDefinition.healthKey
        let system = GoDeeper.system(profile: target.issue.profile, cardText: cardText, section: model.config.sectionName(section))
        let history = turns, chosen = model.settings.chatModel

        asking = Task { @MainActor in
            defer { asking = nil }
            @MainActor func update(_ change: (inout Message) -> Void) {
                if let i = messages.firstIndex(where: { $0.id == answerID }) { change(&messages[i]) }
            }
            do {
                let answer = try await ClaudeClient.ask(model: chosen, system: system, turns: history) { soFar in
                    update { $0.text = soFar }
                }
                update { $0.text = answer.text; $0.question = question }
                turns.append(GoDeeper.Turn(fromReader: false, text: answer.text))
                if answer.truncated { messages.append(Message(role: .note, text: "That answer was cut short. Ask for the rest.")) }
            } catch {
                // Keep whatever arrived before the stop or the failure, and keep the turns alternating.
                let partial = messages.first { $0.id == answerID }?.text ?? ""
                if partial.isEmpty {
                    messages.removeAll { $0.id == answerID }
                    turns.removeLast()
                } else {
                    turns.append(GoDeeper.Turn(fromReader: false, text: partial))
                }
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled {
                    messages.append(Message(role: .note, text: (error as? LocalizedError)?.errorDescription ?? "Something interrupted the answer. Ask again."))
                }
            }
        }
    }
}
