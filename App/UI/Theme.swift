import SwiftUI
import UIKit
import SurfCore

/// Dark, monochrome, one ocean-blue accent used only for "met" and "moving".
enum Theme {
    static let bg = Color(red: 0x0A / 255, green: 0x0B / 255, blue: 0x0D / 255)
    static let card = Color(red: 0x15 / 255, green: 0x17 / 255, blue: 0x1A / 255)
    static let cardDeep = Color(red: 0x12 / 255, green: 0x14 / 255, blue: 0x17 / 255)
    static let line = Color(red: 0x2A / 255, green: 0x2D / 255, blue: 0x31 / 255)
    static let text = Color(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEF / 255)
    static let secondary = Color(red: 0x9B / 255, green: 0x9C / 255, blue: 0x98 / 255)
    static let accent = Color(red: 0x5D / 255, green: 0xB0 / 255, blue: 0xF0 / 255)

    /// Headlines in Instrument Serif, scaling with Dynamic Type. Falls back to the system serif
    /// if the font file isn't in the bundle.
    static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .title, italic: Bool = false) -> Font {
        let name = italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size, relativeTo: style) }
        let fallback = Font.system(size: size, design: .serif)
        return italic ? fallback.italic() : fallback
    }
}

/// Small capitals label: "THIS WEEK", "PROGRESS".
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .tracking(1.6)
            .foregroundStyle(Theme.secondary)
    }
}

/// "SURF AT 60 · 599 days" over a thin horizon line that fills toward the goal date.
struct HorizonHeader<Trailing: View>: View {
    @Environment(AppModel.self) private var model
    let trailing: Trailing

    init(@ViewBuilder trailing: () -> Trailing) { self.trailing = trailing() }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                (Text(model.config.goal.title.uppercased()).fontWeight(.semibold).foregroundStyle(Theme.text)
                 + Text(model.daysLeft.map { " · \($0) days" } ?? "").foregroundStyle(Theme.secondary))
                    .font(.caption)
                    .tracking(1.6)
                    .accessibilityLabel(model.daysLeft.map { "\(model.config.goal.title), \($0) days to go" } ?? model.config.goal.title)
                Spacer()
                trailing
            }
            .frame(minHeight: 28)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line)
                    Rectangle().fill(Theme.accent).frame(width: geo.size.width * model.horizon)
                }
            }
            .frame(height: 1)
            .accessibilityHidden(true)
        }
    }
}

extension HorizonHeader where Trailing == EmptyView {
    init() { self.init { EmptyView() } }
}

/// A thin progress line: accent fill from the start, a knob at the current value, a tick at the goal.
struct ProgressLine: View {
    var progress: Double      // 0...1
    var reached: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = w * min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 2)
                Capsule().fill(Theme.accent).frame(width: x, height: 2)
                if reached {
                    Circle().fill(Theme.accent).frame(width: 12, height: 12).offset(x: w - 10)
                } else {
                    RoundedRectangle(cornerRadius: 1).fill(Theme.secondary).frame(width: 2, height: 12).offset(x: w - 2)
                    Circle().fill(Theme.text).frame(width: 10, height: 10).offset(x: x - 5)
                }
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Theme.text, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Theme.bg)
        }
        .buttonStyle(.plain)
    }
}

/// A selectable chip (duration choices, commit rows).
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Theme.accent.opacity(0.16) : Theme.cardDeep, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.accent : Theme.line, lineWidth: 1))
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

func formatValue(_ value: Double) -> String { CheckinsFile.number(value) }

/// "Nov 9" from "2026-11-09".
func shortDay(_ day: String) -> String {
    let p = day.split(separator: "-").compactMap { Int($0) }
    let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    guard p.count == 3, (1...12).contains(p[1]) else { return day }
    return "\(names[p[1] - 1]) \(p[2])"
}
