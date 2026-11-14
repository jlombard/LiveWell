import SwiftUI
import LiveWellCore

/// Wealth's section home: the board, "why you own it". One row per holding with its share of the
/// account, a status pill and the next thing that matters. A calm analyst's voice; no prices.
struct WealthBoardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = model.wealth.rows(today: model.today)
        let written = rows.filter { $0.status != .notWritten }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Wealth · long lens")
                Text("Why you own it").font(Theme.serif(38, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader).padding(.top, 6)

                if rows.isEmpty {
                    Text("Import your holdings in Settings (the gear on Today) to start: a CSV of positions from your brokerage.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 18)
                } else if let number = model.wealthNumber {
                    (Text(number.text).font(Theme.serif(34, relativeTo: .title)) + Text("  " + number.label).font(.subheadline).foregroundColor(Theme.secondary))
                        .foregroundStyle(Theme.text).padding(.top, 18)
                        .accessibilityLabel("\(number.text) \(number.label), across your holdings")
                } else {
                    Text(Keychain.finnhubKey == nil ? "Add a Finnhub key in Settings to see the week\u{2019}s change."
                                                    : "The week\u{2019}s change appears after the next two closes are recorded.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 18)
                }
                if !rows.isEmpty {
                    Text(Wealth.next(rows)).font(.subheadline).foregroundStyle(Theme.text).padding(.top, 6)
                    // The discipline line: only what exists yet.
                    Text("Reasons written \(written) of \(rows.count)").font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 14)
                }

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                      NavigationLink(value: Route.holding(row.ticker)) {
                        HStack(alignment: .center, spacing: 12) {
                            StatusDot(status: row.status)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                                // An Ask answer for this holding that is arriving or waiting to be read comes first.
                                switch model.ask.state(AskStore.key(Wealth.sectionKey, row.ticker)) {
                                case .answering: Text("Ask is answering\u{2026}").font(.footnote).foregroundStyle(Theme.accent)
                                case .ready: Text("Answer ready in Ask").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                                case .idle: Text(row.next).font(.footnote).foregroundStyle(Theme.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(row.share.map { "\(Int(($0 * 100).rounded()))%" } ?? "\u{2013}")
                                    .font(.body.monospacedDigit()).foregroundStyle(Theme.text)
                                Text(row.status.pill).font(.caption2.weight(.medium)).foregroundStyle(Theme.text)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .overlay(Capsule().stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: row.status == .notWritten ? [3, 3] : [])))
                            }
                        }
                        .frame(minHeight: 64)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.name), \(row.share.map { "\(Int(($0 * 100).rounded())) percent of the account" } ?? "share not known yet"), \(row.status.pill), \(row.next)")
                      }
                      .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)

                // Today's edition and past issues, once Build Wealth has published.
                if let cover = model.editions.first(where: { $0.section == Wealth.sectionKey }) {
                    Eyebrow("Today\u{2019}s edition").padding(.top, 24).padding(.bottom, 10)
                    EditionCoverRow(cover: cover)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                if !rows.isEmpty {
                    NavigationLink(value: Route.ask(Wealth.sectionKey, nil)) {
                        Label(model.ask.state(AskStore.key(Wealth.sectionKey, nil)) == .ready ? "Ask Wealth · answer ready"
                              : (model.ask.state(AskStore.key(Wealth.sectionKey, nil)) == .answering ? "Ask Wealth · answering\u{2026}" : "Ask Wealth"),
                              systemImage: "bubble.left").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GhostButton(palette: .normal)).padding(.top, 18)
                }
                if let note = Wealth.concentration(rows, limit: 0.4) {
                    // 40% is the limit Joe set for one holding (Nov 13, 2026).
                    Text(note + " Your limit for one holding is 40%. Worth knowing; not a prompt to act.")
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 14)
                }
                if let day = model.wealth.book.latestDay {
                    Text("Closing prices through \(shortDay(day)). Holdings from \(model.wealth.importedOn.map(shortDay) ?? "your import").")
                        .font(.caption2).foregroundStyle(Theme.secondary).padding(.top, 14)
                }
                Text("Education and decision support, not buy or sell advice.").font(.caption2).foregroundStyle(Theme.secondary).padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .refreshable { await model.wealth.refresh() }
    }
}

/// A holding's state as a dot: dashed when its reasons aren't written, a ring when they hold,
/// filled when something needs a look. Shape and weight, not colour.
struct StatusDot: View {
    let status: Wealth.Status
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch status {
            case .notWritten: Circle().stroke(Theme.secondary.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
            case .stillTrue: Circle().stroke(Theme.text, lineWidth: 2)
            case .check: Circle().fill(Theme.text.opacity(0.55)).overlay(Circle().stroke(Theme.text, lineWidth: 2))
            case .dealBreaker: Circle().fill(Theme.text)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
