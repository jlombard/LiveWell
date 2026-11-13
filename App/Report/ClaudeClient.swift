import Foundation
import Security
import LiveWellCore

/// The Go deeper chat's connection to Claude: one streaming Messages API request per question,
/// sent straight from the phone with the reader's own API key.
enum ClaudeClient {
    static let models: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"), ("claude-sonnet-5-5", "Claude Sonnet 5.5"), ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]
    static let defaultModel = "claude-opus-5-5"

    struct Answer { var text: String; var truncated: Bool }

    enum Failure: LocalizedError {
        case noKey, badKey, busy, rateLimited, refused, empty, other(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your Anthropic API key in Settings to ask questions."
            case .badKey: return "That API key wasn't accepted. Check it in Settings."
            case .busy: return "Claude is busy right now. Try again in a moment."
            case .rateLimited: return "Too many questions at once, or you've hit a usage limit. Try again in a bit."
            case .refused: return "Claude couldn't answer that one. Try asking it a different way."
            case .empty: return "No answer came back. Try rephrasing."
            case .other(let message): return message
            }
        }
    }

    /// Streams an answer. `onText` gets the whole answer so far each time more arrives.
    static func ask(model: String, system: String, turns: [GoDeeper.Turn],
                    onText: @escaping @MainActor (String) -> Void) async throws -> Answer {
        guard let key = Keychain.apiKey, !key.isEmpty else { throw Failure.noKey }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "stream": true,
            "system": system,
            "output_config": ["effort": "medium"],
            "messages": GoDeeper.window(turns).map { ["role": $0.fromReader ? "user" : "assistant", "content": $0.text] },
        ]
        // If a safety classifier declines, let the API retry on its default fallback model.
        // Haiku has no server-side fallback.
        if !model.contains("haiku") {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var raw = Data()
            for try await byte in bytes { raw.append(byte); if raw.count > 20_000 { break } }
            throw failure(status: status, body: raw)
        }

        var text = "", stop = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:"),
                  let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                   let piece = delta["text"] as? String {
                    text += piece
                    let soFar = text
                    await onText(soFar)
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String { stop = reason }
            case "error":
                let error = event["error"] as? [String: Any]
                if text.isEmpty { throw failure(type: error?["type"] as? String, message: error?["message"] as? String) }
            default: break
            }
        }
        if stop == "refusal" && text.isEmpty { throw Failure.refused }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw Failure.empty }
        return Answer(text: text, truncated: stop == "max_tokens")
    }

    private static func failure(status: Int, body: Data) -> Failure {
        let error = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? [String: Any]
        switch status {
        case 401: return .badKey
        case 429: return .rateLimited
        case 500...: return .busy
        default: return failure(type: error?["type"] as? String, message: error?["message"] as? String ?? "Claude returned an error (\(status)).")
        }
    }

    private static func failure(type: String?, message: String?) -> Failure {
        switch type {
        case "authentication_error": return .badKey
        case "rate_limit_error": return .rateLimited
        case "overloaded_error", "api_error": return .busy
        default: return .other(message ?? "Something interrupted the answer. Ask again.")
        }
    }
}

/// The API key lives in the iOS Keychain, on this device only. It is never written to the
/// Health Glance folder or to the app's settings files.
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "ink.boundless.livewell.anthropic",
        kSecAttrAccount as String: "api-key",
    ]

    static var apiKey: String? {
        get {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            var q = query
            q[kSecValueData as String] = Data(value.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
