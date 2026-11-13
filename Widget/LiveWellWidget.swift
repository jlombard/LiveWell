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

/// The app's colours, repeated here because the widget can't see the app's Theme.
private enum Ink {
    static let bg = Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255)
    static let text = Color(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEF / 255)
    static let secondary = Color(red: 0x9B / 255, green: 0x9C / 255, blue: 0x98 / 255)
    static let line = Color(red: 0x2A / 255, green: 0x2D / 255, blue: 0x31 / 255)
    static let accent = Color(red: 0x5D / 255, green: 0xB0 / 255, blue: 0xF0 / 255)
}

private extension WidgetSnapshot.Icon {
    var symbolName: String { symbol ?? HabitSymbol.name(key) }
}

/// Five habit icons in a row: lit when met, dim when not. Optionally with the count under each.
struct HabitIcons: View {
    @Environment(\.widgetRenderingMode) private var mode
    let icons: [WidgetSnapshot.Icon]
    var size: CGFloat = 15
    var counts = false
    /// On the lock screen everything is one colour; on the home screen a met habit takes the accent.
    var colored = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(icons, id: \.key) { icon in
                VStack(spacing: 3) {
                    Image(systemName: icon.symbolName)
                        .font(.system(size: size, weight: icon.met ? .bold : .regular))
                        .foregroundStyle(colored && icon.met && mode == .fullColor ? Ink.accent : (colored ? Ink.text : .primary))
                        .opacity(icon.met ? 1 : 0.35)
                        .widgetAccentable(icon.met)
                        .frame(height: size + 3)
                    if counts {
                        Text(icon.count ?? "\u{2013}")
                            .font(.system(size: 11, weight: icon.met ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(icon.met ? Ink.text : Ink.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(icon.name), \(counts ? (icon.count ?? "not measured") + ", " : "")\(icon.met ? "met" : "not yet met")")
            }
        }
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
            HabitIcons(icons: snapshot.icons)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Lock screen circle: Exercise minutes toward the goal.
struct CircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if let minutes = snapshot.activeMinutes {
            Gauge(value: min(minutes, snapshot.activeGoal), in: 0...max(1, snapshot.activeGoal)) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text("\(Int(minutes))")
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Active minutes, \(Int(minutes)) of \(Int(snapshot.activeGoal))")
        } else {
            Image(systemName: "figure.walk").opacity(0.35)
                .accessibilityLabel("Active minutes, not measured")
        }
    }
}

/// Home screen small, and StandBy: "N days" in small type, the Today line, five icons lit or dim.
struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let days = snapshot.daysLeft {
                Text("\(days) days").font(.caption2).tracking(1.2).textCase(.uppercase).foregroundStyle(Ink.secondary)
                    .accessibilityLabel("\(days) days to \(snapshot.title ?? "the goal")")
            }
            Spacer(minLength: 4)
            Text(snapshot.line)
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(Ink.text)
                .lineLimit(3).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 6)
            HabitIcons(icons: snapshot.icons, size: 14, colored: true)
        }
    }
}

/// Home screen medium: the Today line, five icons with counts, five progress bars as thin lines
/// with the current dot. No numbers on the bars.
struct MediumView: View {
    @Environment(\.widgetRenderingMode) private var mode
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                if let days = snapshot.daysLeft {
                    Text("\(days) days").font(.caption2).tracking(1.2).textCase(.uppercase).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 4)
                Text(snapshot.line)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Ink.text)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 8)
                HabitIcons(icons: snapshot.icons, size: 14, counts: true, colored: true)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 0) {
                let bars = snapshot.bars ?? []
                ForEach(bars, id: \.key) { bar in
                    BarLine(bar: bar, accent: mode == .fullColor ? Ink.accent : Ink.text).frame(maxHeight: .infinity)
                }
                if bars.isEmpty {
                    Text("Progress appears once the Mac has built the dashboard.")
                        .font(.caption2).foregroundStyle(Ink.secondary).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 112)
        }
    }
}

private struct BarLine: View {
    let bar: WidgetSnapshot.Bar
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, x = w * bar.progress, y = geo.size.height / 2
            ZStack(alignment: .topLeading) {
                Capsule().fill(Ink.line).frame(width: w, height: 2).offset(y: y - 1)
                Capsule().fill(accent).frame(width: x, height: 2).offset(y: y - 1).widgetAccentable()
                Circle().fill(bar.reached ? accent : Ink.text).frame(width: 8, height: 8)
                    .offset(x: min(max(0, x - 4), w - 8), y: y - 4).widgetAccentable(bar.reached)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.label), \(Int((bar.progress * 100).rounded())) percent of the way\(bar.reached ? ", reached" : "")")
    }
}

struct LiveWellWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SurfEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView(snapshot: entry.snapshot).containerBackground(.clear, for: .widget).widgetURL(DeepLink.today)
        case .systemSmall:
            // iOS drops this background in the tinted and clear home-screen modes, and in StandBy.
            SmallView(snapshot: entry.snapshot).containerBackground(Ink.bg, for: .widget).widgetURL(DeepLink.today)
        case .systemMedium:
            MediumView(snapshot: entry.snapshot).containerBackground(Ink.bg, for: .widget).widgetURL(DeepLink.today)
        default:
            RectangularView(snapshot: entry.snapshot).containerBackground(.clear, for: .widget).widgetURL(DeepLink.today)
        }
    }
}

struct LiveWellWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiveWellWidget", provider: SurfProvider()) { entry in
            LiveWellWidgetView(entry: entry)
        }
        .configurationDisplayName("Health")
        .description("Today\u{2019}s one thing, and your habits.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium])
    }
}

// MARK: - Wealth and the combined widget

/// Wealth, small or on the lock screen: the week's change in percent and the one thing to do.
/// Same ink as everything else; no red or green, no prices.
struct WealthView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        let line = snapshot.wealthLine, next = snapshot.wealthNext ?? "Import your holdings in LiveWell."
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 3) {
                Text(line ?? "Wealth").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Text(next).font(.caption).lineLimit(2).opacity(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Wealth").font(.caption2).tracking(1.2).textCase(.uppercase).foregroundStyle(Ink.secondary)
                Spacer(minLength: 4)
                if let line {
                    let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                    Text(parts[0]).font(.system(size: 34, weight: .regular, design: .serif)).foregroundStyle(Ink.text)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if parts.count > 1 { Text(parts[1]).font(.caption).foregroundStyle(Ink.secondary) }
                }
                Spacer(minLength: 6)
                Text(next).font(.caption).foregroundStyle(Ink.text).lineLimit(2).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Medium: the Health line and the Wealth line, one above the other.
struct CombinedView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Link(destination: DeepLink.today) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((snapshot.title ?? "Health") + (snapshot.daysLeft.map { " · \($0) days" } ?? ""))
                            .font(.caption2).tracking(1.2).textCase(.uppercase).foregroundStyle(Ink.secondary)
                        Text(snapshot.line).font(.system(size: 20, weight: .regular, design: .serif)).foregroundStyle(Ink.text)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                    HabitIcons(icons: snapshot.icons, size: 13, colored: true).frame(width: 118)
                }
                .frame(maxHeight: .infinity)
            }
            Rectangle().fill(Ink.line).frame(height: 1)
            Link(destination: DeepLink.wealth) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wealth" + (snapshot.wealthNext.map { " · " + $0.replacingOccurrences(of: ".", with: "") } ?? ""))
                        .font(.caption2).tracking(1.2).textCase(.uppercase).foregroundStyle(Ink.secondary).lineLimit(1)
                    Text(snapshot.wealthLine ?? "Import your holdings in LiveWell")
                        .font(.system(size: 20, weight: .regular, design: .serif)).foregroundStyle(Ink.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

struct WealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiveWellWealth", provider: SurfProvider()) { entry in
            WealthWidgetView(entry: entry)
        }
        .configurationDisplayName("Wealth")
        .description("The week across your holdings, in percent, and the one thing to do.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct WealthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SurfEntry
    var body: some View {
        if family == .accessoryRectangular {
            WealthView(snapshot: entry.snapshot).containerBackground(.clear, for: .widget).widgetURL(DeepLink.wealth)
        } else {
            WealthView(snapshot: entry.snapshot).containerBackground(Ink.bg, for: .widget).widgetURL(DeepLink.wealth)
        }
    }
}

struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiveWellCombined", provider: SurfProvider()) { entry in
            CombinedView(snapshot: entry.snapshot).containerBackground(Ink.bg, for: .widget)
        }
        .configurationDisplayName("Health and Wealth")
        .description("One line from each section.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct LiveWellWidgets: WidgetBundle {
    var body: some Widget {
        LiveWellWidget()
        WealthWidget()
        CombinedWidget()
    }
}
