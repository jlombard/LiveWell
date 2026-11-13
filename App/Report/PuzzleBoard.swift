import SwiftUI
import LiveWellCore

/// "Name the company", playable inside its card: the revenue treemap, clues that unlock with
/// each miss, a guess box with suggestions, the guess log with closeness, then the reveal.
struct PuzzleBoard: View {
    @Environment(AppModel.self) private var model
    let puzzle: Puzzle
    /// The issue date: one puzzle per issue.
    let id: String
    @State private var typed = ""
    @State private var message: String?
    @FocusState private var focused: Bool

    private var game: PuzzleGame { model.puzzles.games[id] ?? PuzzleGame(answer: puzzle.answer) }

    var body: some View {
        if !puzzle.isPlayable {
            Text("This puzzle can\u{2019}t be played in this version of the app.").font(.footnote).foregroundStyle(Theme.secondary)
        } else {
            let game = game
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Revenue by type · \(puzzle.period) · \(puzzle.total)")
                    Treemap(tiles: puzzle.tiles)
                    if let caption = puzzle.caption { Text(caption).font(.footnote).foregroundStyle(Theme.secondary) }
                }

                clues(open: game.cluesOpen(of: puzzle.clues.count))

                if !game.finished { guessBox(game) }

                if !game.guesses.isEmpty {
                    VStack(spacing: 6) { ForEach(game.guesses, id: \.self) { guessRow($0, game) } }
                }

                if game.finished { reveal(game) }
                else {
                    Text("Each guess fills up to three squares: same sector, same industry, same niche. The tree is simplified for the game.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    Text("Source: the company\u{2019}s latest annual report. Named after the reveal.").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func clues(open: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(puzzle.clues.enumerated()), id: \.offset) { index, clue in
                let on = index < open
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 2)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary).frame(width: 18, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(clue.title.uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(on ? Theme.text : Theme.secondary)
                        if on {
                            if !clue.bars.isEmpty { SplitBar(bars: clue.bars) }
                            if !clue.text.isEmpty { Rich(clue.text, font: .subheadline) }
                        } else {
                            Text("Unlocks after a miss").font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func guessBox(_ game: PuzzleGame) -> some View {
        let suggestions = PuzzleCatalog.suggestions(typed, excluding: game.guesses)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField("Type a company", text: $typed)
                    .textInputAutocapitalization(.words).autocorrectionDisabled().focused($focused)
                    .submitLabel(.go).onSubmit { submit(typed) }
                    .padding(12)
                    .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                    .accessibilityLabel("Your guess")
                Button("Guess") { submit(typed) }
                    .font(.headline).frame(minWidth: 72, minHeight: 46)
                    .background(Theme.text, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.bg)
            }
            ForEach(suggestions, id: \.self) { name in
                Button { submit(name) } label: {
                    Text(name).font(.subheadline).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            Text(message ?? game.status(clues: puzzle.clues.count)).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 8)
        }
    }

    private func guessRow(_ name: String, _ game: PuzzleGame) -> some View {
        let n = game.closeness(name), win = name == game.answer
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle().fill(i < n ? (win ? Theme.bg : Theme.text) : Color.clear)
                            .overlay(Rectangle().stroke(win ? Theme.bg : Theme.text, lineWidth: 1))
                            .frame(width: 14, height: 14)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(game.hint(name)).font(.footnote).foregroundStyle(win ? Theme.bg.opacity(0.8) : Theme.secondary)
        }
        .foregroundStyle(win ? Theme.bg : Theme.text)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(win ? Theme.text : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(win ? Color.clear : Theme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(game.hint(name)), \(n) of 3 squares")
    }

    private func reveal(_ game: PuzzleGame) -> some View {
        let fg = game.won ? Theme.bg : Theme.text
        return VStack(alignment: .leading, spacing: 10) {
            Text(game.status(clues: puzzle.clues.count).uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(fg.opacity(0.7))
            Text(puzzle.full).font(Theme.serif(28, relativeTo: .title)).foregroundStyle(fg)
            if !puzzle.why.isEmpty {
                (Text("Why this shape: ").fontWeight(.semibold) + Text(RichText.plain(puzzle.why))).font(.subheadline).foregroundStyle(fg)
            }
            if !puzzle.lesson.isEmpty { Text("The lesson: " + RichText.plain(puzzle.lesson)).font(.subheadline).foregroundStyle(fg) }
            if let line = model.puzzles.line { Text(line).font(.footnote).foregroundStyle(fg.opacity(0.7)) }
            ShareLink(item: game.shareText(number: puzzle.number)) { Label("Share result", systemImage: "square.and.arrow.up") }
                .font(.subheadline.weight(.medium)).foregroundStyle(fg)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .overlay(Capsule().stroke(fg.opacity(0.5), lineWidth: 1))
            // Sources are named only now, so they can't give the answer away.
            ForEach(Array(puzzle.sources.enumerated()), id: \.offset) { _, source in
                SourceLine(source: source, palette: game.won ? .win : .normal)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(game.won ? Theme.text : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(game.won ? Color.clear : Theme.text, lineWidth: 1))
    }

    private func submit(_ raw: String) {
        var next = game
        switch next.guess(raw) {
        case .accepted:
            typed = ""; message = nil
            model.puzzles.games[id] = next
            if next.finished {
                focused = false
                UINotificationFeedbackGenerator().notificationOccurred(next.won ? .success : .warning)
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case .unknown: message = "Pick a company from the list."
        case .repeated(let name): message = "You already tried \(name)."
        case .over: break
        }
    }
}

/// The revenue treemap: area is share of the total. Labels are generic, so they don't name the company.
private struct Treemap: View {
    let tiles: [Puzzle.Tile]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    let w = geo.size.width * tile.w, h = geo.size.height * tile.h
                    VStack(alignment: .leading, spacing: 1) {
                        Spacer(minLength: 0)
                        // A sliver too thin for its number stays blank; the caption and VoiceOver still give it.
                        if !tile.small || (w >= 26 && h >= 14) {
                            Text(String(format: tile.small ? "%.1f" : "%.1f%%", tile.percent))
                                .font(.system(size: tile.small ? 10 : 17, weight: .bold).monospacedDigit()).lineLimit(1)
                        }
                        if !tile.small { Text(tile.label).font(.caption2).lineLimit(3).minimumScaleFactor(0.8) }
                    }
                    .foregroundStyle(Theme.bg)
                    .padding(tile.small ? 2 : 6)
                    .frame(width: max(0, w - 2), height: max(0, h - 2), alignment: tile.small ? .center : .bottomLeading)
                    .background(Theme.text)
                    .offset(x: geo.size.width * tile.x + 1, y: geo.size.height * tile.y + 1)
                }
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Treemap of revenue: " + tiles.map { "\($0.label) \(String(format: "%.1f", $0.percent)) percent" }.joined(separator: ", "))
    }
}

/// One stacked bar for a split such as sales by region, told apart by fill, not colour.
private struct SplitBar: View {
    let bars: [Puzzle.Bar]

    var body: some View {
        let total = max(bars.reduce(0) { $0 + $1.pct }, 0.0001)
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                        Rectangle()
                            .fill(Theme.text.opacity(index == 0 ? 1 : (index == 1 ? 0.55 : 0.25)))
                            .frame(width: max(0, (geo.size.width - CGFloat(bars.count - 1) * 2) * bar.pct / total))
                    }
                }
            }
            .frame(height: 20)
            Text(bars.map { "\($0.label) \(CheckinsFile.number($0.pct))%" }.joined(separator: "  ·  "))
                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bars.map { "\($0.label) \(CheckinsFile.number($0.pct)) percent" }.joined(separator: ", "))
    }
}
