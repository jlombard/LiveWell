import SwiftUI
import WebKit
import LiveWellCore

/// The five figure types an issue can carry, drawn to match the web report.
struct FigureView: View {
    let figure: ReportFigure
    let palette: CardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                switch figure.type {
                case "spark": SparkFigure(figure: figure, palette: palette)
                case "scale": ScaleFigure(figure: figure, palette: palette)
                case "pairs": PairsFigure(rows: figure.rows, palette: palette)
                case "tiles": TilesFigure(items: figure.items, palette: palette)
                case "svg": if let svg = figure.svg { DrawingFigure(svg: svg, palette: palette) }
                default: EmptyView()
                }
            }
            .accessibilityElement(children: figure.alt == nil ? .contain : .ignore)
            .accessibilityLabel(figure.alt ?? "")
            if let caption = figure.caption {
                Rich(caption, font: .footnote, color: palette.secondary, linkColor: palette.accent)
            }
        }
    }
}

/// A line of readings with marked points (drawn in the web page's 340 x 150 space).
private struct SparkFigure: View {
    let figure: ReportFigure
    let palette: CardPalette

    var body: some View {
        Canvas { context, size in
            let points = figure.points
            guard !points.isEmpty else { return }
            let k = size.width / 340
            let W: CGFloat = 340, H: CGFloat = 150, L: CGFloat = 8, R: CGFloat = 8, T: CGFloat = 26, B: CGFloat = 24
            let values = points.map(\.value)
            let top = figure.max ?? (values.max() ?? 1) * 1.05, bottom = figure.min ?? 0
            let span = top - bottom == 0 ? 1 : top - bottom
            func x(_ i: Int) -> CGFloat { (L + CGFloat(i) * (W - L - R) / CGFloat(max(1, points.count - 1))) * k }
            func y(_ v: Double) -> CGFloat { (T + CGFloat(1 - (v - bottom) / span) * (H - T - B)) * k }
            let ink = palette.text
            let base = (H - B) * k

            var axis = Path(); axis.move(to: CGPoint(x: L * k, y: base)); axis.addLine(to: CGPoint(x: (W - R) * k, y: base))
            context.stroke(axis, with: .color(ink.opacity(0.25)), lineWidth: 1)

            var area = Path(); area.move(to: CGPoint(x: x(0), y: base))
            for (i, p) in points.enumerated() { area.addLine(to: CGPoint(x: x(i), y: y(p.value))) }
            area.addLine(to: CGPoint(x: x(points.count - 1), y: base)); area.closeSubpath()
            context.fill(area, with: .color(ink.opacity(0.08)))

            let solid = figure.dashLast ? points.count - 1 : points.count
            var line = Path()
            for i in 0..<solid {
                let pt = CGPoint(x: x(i), y: y(points[i].value))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            context.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 2.5 * k, lineJoin: .round))
            if figure.dashLast, points.count >= 2 {
                var dash = Path()
                dash.move(to: CGPoint(x: x(points.count - 2), y: y(points[points.count - 2].value)))
                dash.addLine(to: CGPoint(x: x(points.count - 1), y: y(points[points.count - 1].value)))
                context.stroke(dash, with: .color(ink), style: StrokeStyle(lineWidth: 2 * k, dash: [3 * k, 3 * k]))
            }
            for (i, p) in points.enumerated() {
                let r = (figure.marks[i] != nil ? 4 : 2.2) * k
                let dot = Path(ellipseIn: CGRect(x: x(i) - r, y: y(p.value) - r, width: 2 * r, height: 2 * r))
                if figure.dashLast && i == points.count - 1 { context.fill(dot, with: .color(palette.background)) }
                else { context.fill(dot, with: .color(ink)) }
                context.stroke(dot, with: .color(ink), lineWidth: 1.5 * k)
            }
            for (i, mark) in figure.marks where points.indices.contains(i) {
                let anchor: UnitPoint = i == 0 ? .leading : (i >= points.count - 2 ? .trailing : .center)
                let below = mark.below ?? false
                let at = CGPoint(x: x(i), y: y(points[i].value) + (below ? 13 : -13) * k)
                context.draw(Text(mark.text).font(.system(size: max(11, 10 * k), weight: .medium)).foregroundColor(ink), at: at, anchor: anchor)
            }
            let small = Font.system(size: max(10, 9 * k))
            context.draw(Text(points[0].label).font(small).foregroundColor(palette.secondary),
                         at: CGPoint(x: x(0), y: (H - 8) * k), anchor: .leading)
            context.draw(Text(points[points.count - 1].label).font(small).foregroundColor(palette.secondary),
                         at: CGPoint(x: x(points.count - 1), y: (H - 8) * k), anchor: .trailing)
        }
        .aspectRatio(340.0 / 150.0, contentMode: .fit)
    }
}

/// A range with a shaded band, "you" and "goal" (340 x 92 space).
private struct ScaleFigure: View {
    let figure: ReportFigure
    let palette: CardPalette

    var body: some View {
        Canvas { context, size in
            guard let a = figure.min, let b = figure.max, b > a else { return }
            let k = size.width / 340, ink = palette.text
            func X(_ n: Double) -> CGFloat { (14 + CGFloat((n - a) / (b - a)) * (340 - 28)) * k }
            let label = Font.system(size: max(10, 10 * k))
            if figure.band.count == 2 {
                let rect = CGRect(x: X(figure.band[0]), y: 30 * k, width: X(figure.band[1]) - X(figure.band[0]), height: 14 * k)
                context.fill(Path(rect), with: .color(ink.opacity(0.18)))
                context.draw(Text(figure.bandLabel ?? "").font(.system(size: max(9, 9.5 * k))).foregroundColor(palette.secondary),
                             at: CGPoint(x: rect.midX, y: 22 * k), anchor: .center)
            }
            var axis = Path(); axis.move(to: CGPoint(x: X(a), y: 44 * k)); axis.addLine(to: CGPoint(x: X(b), y: 44 * k))
            context.stroke(axis, with: .color(ink), lineWidth: 1.5)
            for n in figure.ticks.isEmpty ? [a, b] : figure.ticks {
                var tick = Path(); tick.move(to: CGPoint(x: X(n), y: 44 * k)); tick.addLine(to: CGPoint(x: X(n), y: 49 * k))
                context.stroke(tick, with: .color(ink), lineWidth: 1)
                context.draw(Text(ReportFigure.number(n)).font(label).foregroundColor(palette.secondary),
                             at: CGPoint(x: X(n), y: 58 * k), anchor: .center)
            }
            if let you = figure.you {
                var mark = Path(); mark.move(to: CGPoint(x: X(you), y: 26 * k)); mark.addLine(to: CGPoint(x: X(you), y: 48 * k))
                context.stroke(mark, with: .color(palette.accent), lineWidth: 3)
                context.draw(Text(figure.youLabel ?? "you \(ReportFigure.number(you))").font(label.weight(.semibold)).foregroundColor(ink),
                             at: CGPoint(x: min(max(X(you), 30 * k), 310 * k), y: 9 * k), anchor: .center)
            }
            if let goal = figure.goal {
                var tri = Path(); tri.move(to: CGPoint(x: X(goal), y: 68 * k))
                tri.addLine(to: CGPoint(x: X(goal) - 5 * k, y: 76 * k)); tri.addLine(to: CGPoint(x: X(goal) + 5 * k, y: 76 * k)); tri.closeSubpath()
                context.fill(tri, with: .color(ink))
                context.draw(Text(figure.goalLabel ?? "goal \(ReportFigure.number(goal))").font(label).foregroundColor(ink),
                             at: CGPoint(x: min(max(X(goal), 30 * k), 310 * k), y: 86 * k), anchor: .center)
            }
        }
        .aspectRatio(340.0 / 96.0, contentMode: .fit)
    }
}

/// Then-and-now bars: "Chest press · the push   103 → 184".
private struct PairsFigure: View {
    let rows: [ReportFigure.Pair]
    let palette: CardPalette

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).font(.footnote).foregroundStyle(palette.text)
                        Spacer()
                        Text("\(ReportFigure.number(row.from)) → \(ReportFigure.number(row.to))")
                            .font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(palette.text)
                    }
                    GeometryReader { geo in
                        let top = max(row.from, row.to, 0.0001)
                        VStack(spacing: 3) {
                            Capsule().fill(palette.secondary.opacity(0.5)).frame(width: geo.size.width * row.from / top, height: 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Capsule().fill(palette.accent).frame(width: geo.size.width * row.to / top, height: 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(height: 13)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.label): from \(ReportFigure.number(row.from)) to \(ReportFigure.number(row.to))")
            }
        }
    }
}

/// The five habit tiles as an issue shows them.
private struct TilesFigure: View {
    let items: [ReportFigure.Tile]
    let palette: CardPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, tile in
                VStack(spacing: 3) {
                    Text(tile.value).font(.headline.monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
                    Text(tile.name).font(.caption2).minimumScaleFactor(0.7).lineLimit(1)
                }
                .foregroundStyle(tile.met ? palette.background : palette.text)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, 2)
                .background(tile.met ? palette.text : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tile.met ? Color.clear : palette.line, lineWidth: 1))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(tile.name): \(tile.value)\(tile.met ? ", goal met" : "")")
            }
        }
    }
}

/// A line drawing (pose, muscle map) supplied as SVG. Drawn by WebKit, in the card's text colour.
private struct DrawingFigure: View {
    let svg: String
    let palette: CardPalette

    /// width / height from the viewBox, defaulting to square.
    private var ratio: CGFloat {
        guard let r = svg.range(of: "viewBox=\"") else { return 1 }
        let numbers = svg[r.upperBound...].prefix { $0 != "\"" }.split { $0 == " " || $0 == "," }.compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return 1 }
        return CGFloat(numbers[2] / numbers[3])
    }

    var body: some View {
        SVGWeb(svg: svg, color: palette.css)
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxHeight: 240)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }
}

private struct SVGWeb: UIViewRepresentable {
    let svg: String
    let color: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false   // drawings only, never scripts
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:transparent;color:\(color)}
        svg{display:block;width:100%;height:100%}</style>\(svg)
        """
        if context.coordinator.loaded != html {
            context.coordinator.loaded = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loaded = "" }
}
