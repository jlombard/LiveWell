import WidgetKit
import SwiftUI
import LiveWellCore

struct SurfEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SurfProvider: TimelineProvider {
    func placeholder(in context: Context) -> SurfEntry {
        SurfEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SurfEntry) -> Void) {
        completion(SurfEntry(date: .now, snapshot: AppGroup.readSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SurfEntry>) -> Void) {
        // The app reloads the widget whenever something changes; this is only a backstop.
        let entry = SurfEntry(date: .now, snapshot: AppGroup.readSnapshot() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

/// Lock screen: the Today line, then five habit icons, lit when met and dim when not. No numbers.
struct RectangularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(snapshot.line)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 0) {
                ForEach(snapshot.icons, id: \.key) { icon in
                    Image(systemName: HabitSymbol.name(icon.key))
                        .font(.system(size: 15, weight: icon.met ? .bold : .regular))
                        .opacity(icon.met ? 1 : 0.35)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("\(icon.name), \(icon.met ? "met" : "not yet met")")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Lock screen circle: active minutes toward the goal.
struct CircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if let minutes = snapshot.activeMinutes {
            Gauge(value: min(minutes, snapshot.activeGoal), in: 0...max(1, snapshot.activeGoal)) {
                Image(systemName: HabitSymbol.name("active"))
            } currentValueLabel: {
                Text("\(Int(minutes))")
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Active minutes, \(Int(minutes)) of \(Int(snapshot.activeGoal))")
        } else {
            Image(systemName: HabitSymbol.name("active")).opacity(0.35)
                .accessibilityLabel("Active minutes, not measured")
        }
    }
}

struct LiveWellWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SurfEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: CircularView(snapshot: entry.snapshot)
            default: RectangularView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(DeepLink.today)
    }
}

@main
struct LiveWellWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiveWellWidget", provider: SurfProvider()) { entry in
            LiveWellWidgetView(entry: entry)
        }
        .configurationDisplayName("LiveWell")
        .description("Today\u{2019}s one thing, and your five habits.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}
