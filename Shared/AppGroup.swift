import Foundation
import LiveWellCore

/// The container the app and the widget share. The id must match both .entitlements files
/// (set in project.yml).
enum AppGroup {
    static let id = "group.ink.boundless.livewell"

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = container?.appendingPathComponent(WidgetSnapshot.fileName),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true when the snapshot changed (so the widget should reload).
    @discardableResult
    static func writeSnapshot(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = container?.appendingPathComponent(WidgetSnapshot.fileName) else { return false }
        if let old = readSnapshot(), old.sameContent(as: snapshot) { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

enum DeepLink {
    static let today = URL(string: "livewell://today")!
    static let checkin = URL(string: "livewell://checkin")!
    static let report = URL(string: "livewell://report")!
}

/// SF Symbols for habits whose definition names none (configs and snapshots saved by older builds).
/// New code reads the symbol from the habit's definition: `HabitStatus.symbol`, `WidgetSnapshot.Icon.symbol`.
enum HabitSymbol {
    static func name(_ key: String) -> String {
        switch key {
        case "lift": return "dumbbell.fill"
        case "row": return "figure.rower"
        case "yoga": return "figure.yoga"
        case "active": return "figure.walk"
        case "plan": return "fork.knife"
        default: return "circle"
        }
    }
}
