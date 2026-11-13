import Foundation
import Observation
import UIKit
import LiveWellCore

/// Ask conversations, kept apart from the screen so an answer keeps arriving while he looks at
/// something else, and kept on the phone so a conversation is still there when he comes back.
@MainActor
@Observable
final class AskStore {
    struct Message: Identifiable, Codable, Equatable {
        enum Role: String, Codable { case reader, claude, note }
        var id = UUID()
        var role: Role
        /// For Claude: the reply as it arrived, proposal tags included.
        var text: String
        var finished = true

        /// The reply without its proposal tags, and the lines it proposes.
        var parts: (text: String, proposals: [Proposals.Proposal]) { Proposals.split(text) }
    }

    struct Session: Codable, Equatable {
        var messages: [Message] = []
        var lens: String?
        /// An answer finished while he was elsewhere.
        var unread = false
    }

    enum State { case idle, answering, ready }

    private(set) var sessions: [String: Session] = [:]
    private(set) var running: Set<String> = []
    /// The conversation on screen right now, if any.
    var visible: String?
    private var tasks: [String: Task<Void, Never>] = [:]
    private static let fileName = "ask.json"

    init() {
        sessions = AppModel.load(Self.fileName) ?? [:]
        // An answer that was still arriving when the app last closed can't be resumed.
        for key in sessions.keys {
            if let i = sessions[key]?.messages.lastIndex(where: { !$0.finished }) {
                if sessions[key]!.messages[i].text.isEmpty { sessions[key]!.messages.remove(at: i) }
                else {
                    sessions[key]!.messages[i].finished = true
                    sessions[key]!.messages.append(Message(role: .note, text: "That answer stopped part-way. Ask it to continue."))
                }
            }
        }
    }

    static func key(_ section: String, _ ticker: String?) -> String { section + "|" + (ticker ?? "") }

    func session(_ key: String) -> Session { sessions[key] ?? Session() }

    func state(_ key: String) -> State {
        running.contains(key) ? .answering : (sessions[key]?.unread == true ? .ready : .idle)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: AppModel.supportURL(Self.fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func setLens(_ key: String, _ lens: String?) { sessions[key, default: Session()].lens = lens; save() }

    func seen(_ key: String) {
        if sessions[key]?.unread == true { sessions[key]?.unread = false; save() }
    }

    /// Starts the conversation over. The draft and the lenses done are kept; they live elsewhere.
    func clear(_ key: String) {
        stop(key)
        sessions[key] = nil
        save()
    }

    func stop(_ key: String) { tasks[key]?.cancel() }

    private func turns(_ key: String) -> [GoDeeper.Turn] {
        session(key).messages.compactMap { m in
            switch m.role {
            case .reader: return GoDeeper.Turn(fromReader: true, text: m.text)
            case .claude: return m.text.isEmpty ? nil : GoDeeper.Turn(fromReader: false, text: m.text)
            case .note: return nil
            }
        }
    }

    /// Sends a question. The answer streams into the session whether or not its screen is showing.
    func send(_ key: String, _ raw: String, system: String, model: String, webSearch: Bool) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !running.contains(key) else { return }
        sessions[key, default: Session()].messages.append(Message(role: .reader, text: question))
        let history = turns(key)
        let answer = Message(role: .claude, text: "", finished: false)
        sessions[key]!.messages.append(answer)
        running.insert(key)
        save()

        func update(_ change: (inout Message) -> Void) {
            guard let i = sessions[key]?.messages.firstIndex(where: { $0.id == answer.id }) else { return }
            change(&sessions[key]!.messages[i])
        }

        tasks[key] = Task { @MainActor in
            // A little extra time if he leaves the app mid-answer; iOS allows about half a minute.
            var background = UIBackgroundTaskIdentifier.invalid
            background = UIApplication.shared.beginBackgroundTask(withName: "ask") {
                // Time is up: stop cleanly so what arrived is kept.
                Task { @MainActor in
                    self.tasks[key]?.cancel()
                    if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
                }
            }
            defer {
                running.remove(key); tasks[key] = nil
                if visible != key, sessions[key] != nil { sessions[key]!.unread = true }
                save()
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            }
            do {
                let result = try await ClaudeClient.ask(model: model, system: system, turns: history, webSearch: webSearch) { soFar in
                    update { $0.text = soFar }
                }
                update { $0.text = result.text; $0.finished = true }
                if result.truncated { sessions[key]?.messages.append(Message(role: .note, text: "That answer stopped part-way. Ask it to continue.")) }
            } catch {
                // Keep whatever arrived before the stop or the failure.
                let partial = sessions[key]?.messages.first { $0.id == answer.id }?.text ?? ""
                if partial.isEmpty { sessions[key]?.messages.removeAll { $0.id == answer.id } } else { update { $0.finished = true } }
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if !cancelled {
                    sessions[key]?.messages.append(Message(role: .note, text: (error as? LocalizedError)?.errorDescription ?? "Something interrupted the answer. Ask again."))
                } else if !partial.isEmpty {
                    sessions[key]?.messages.append(Message(role: .note, text: "Stopped. What arrived is kept; ask it to continue if you want the rest."))
                }
            }
        }
    }
}
