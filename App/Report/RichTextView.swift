import SwiftUI
import LiveWellCore

/// Colours for one card. A "win" card is inverted: light card, dark text.
struct CardPalette: Equatable {
    var text: Color
    var secondary: Color
    var background: Color
    var line: Color
    var accent: Color
    /// CSS colour for line drawings.
    var css: String

    static let normal = CardPalette(text: Theme.text, secondary: Theme.secondary, background: Theme.card,
                                    line: Theme.line, accent: Theme.accent, css: "#F4F3EF")
    static let win = CardPalette(text: Theme.bg, secondary: Color(red: 0.32, green: 0.33, blue: 0.34), background: Theme.text,
                                 line: Color(red: 0.78, green: 0.78, blue: 0.75), accent: Color(red: 0.10, green: 0.42, blue: 0.72),
                                 css: "#0A0B0D")
}

extension AttributedString {
    /// Inline HTML from an issue (<em>, <b>, <span class="num">, <a>) as styled text.
    /// - emphasis: the font for <em> runs; nil keeps the base font, italic.
    init(html: String, font: Font, emphasis: Font? = nil, linkColor: Color = Theme.accent) {
        self.init()
        for run in RichText.parse(html) {
            var piece = AttributedString(run.text)
            var f = font
            if run.emphasis { f = emphasis ?? font.italic() }
            if run.bold { f = f.weight(.semibold) }
            if run.number { f = f.weight(.semibold).monospacedDigit() }
            piece.font = f
            if let link = run.link, let url = URL(string: link) {
                piece.link = url
                piece.foregroundColor = linkColor
                piece.underlineStyle = .single
            }
            append(piece)
        }
    }
}

/// A paragraph of issue text.
struct Rich: View {
    let html: String
    var font: Font = .body
    var emphasis: Font?
    var color: Color = Theme.text
    var linkColor: Color = Theme.accent

    init(_ html: String, font: Font = .body, emphasis: Font? = nil, color: Color = Theme.text, linkColor: Color = Theme.accent) {
        self.html = html; self.font = font; self.emphasis = emphasis; self.color = color; self.linkColor = linkColor
    }

    var body: some View {
        Text(AttributedString(html: html, font: font, emphasis: emphasis, linkColor: linkColor))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Source: Author et al., Title, Journal, Year." with the title linked.
struct SourceLine: View {
    let source: ReportSource
    let palette: CardPalette

    var body: some View {
        let parts = source.parts
        var text = AttributedString("Source: " + parts.before)
        var link = AttributedString(parts.link)
        if let url = source.url.flatMap(URL.init(string:)) {
            if parts.link.isEmpty { link = AttributedString(" " + (url.host ?? "link")) }
            link.link = url
            link.foregroundColor = palette.accent
            link.underlineStyle = .single
        }
        text.append(link)
        text.append(AttributedString(parts.after))
        return Text(text).font(.footnote).foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}
