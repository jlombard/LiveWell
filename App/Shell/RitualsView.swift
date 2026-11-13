import SwiftUI
import LiveWellCore

/// Rituals: due now, coming up and done recently, across sections.
struct RitualsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = model.rituals
        let due = all.filter { $0.when == .dueNow }
        let coming = all.filter { $0.when == .comingUp }.sorted { ($0.date ?? "") < ($1.date ?? "") }
        let done = all.filter { $0.when == .done }.sorted { ($0.date ?? "") > ($1.date ?? "") }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Rituals").font(Theme.serif(38, relativeTo: .largeTitle)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                Text("Small ceremonies that keep each goal on course.").font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 6)

                Eyebrow("Due now").padding(.top, 22)
                if due.isEmpty {
                    Text(model.folderLinked ? "Nothing due. You\u{2019}re up to date." : "Link the Health Glance folder (the gear on Today) to start.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 10)
                }
                ForEach(due) { ritual in
                    if let route = ritual.route {
                        NavigationLink(value: route) { dueCard(ritual) }.buttonStyle(.plain).padding(.top, 10)
                    } else {
                        dueCard(ritual).padding(.top, 10)
                    }
                }

                if !coming.isEmpty {
                    Eyebrow("Coming up").padding(.top, 24).padding(.bottom, 6)
                    ForEach(coming) { ritual in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(model.ritualDate(ritual)).font(.footnote).foregroundStyle(Theme.secondary).frame(width: 64, alignment: .leading)
                            Text(ritual.title).font(.subheadline).foregroundStyle(Theme.text)
                            Spacer()
                            Text(ritual.kicker).font(.caption).foregroundStyle(Theme.secondary)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        .accessibilityElement(children: .combine)
                    }
                }

                if !done.isEmpty {
                    Eyebrow("Done recently").padding(.top, 24).padding(.bottom, 6)
                    ForEach(done) { ritual in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(model.ritualDate(ritual)).font(.footnote).foregroundStyle(Theme.secondary.opacity(0.8)).frame(width: 64, alignment: .leading)
                            Text(ritual.title).font(.footnote).foregroundStyle(Theme.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .onAppear { model.loadCheckins() }
    }

    private func dueCard(_ ritual: Ritual) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ritual.kicker).font(.caption2).foregroundStyle(Theme.secondary)
                Text(ritual.title).font(.headline).foregroundStyle(Theme.text)
                if !ritual.detail.isEmpty { Text(ritual.detail).font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading) }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
}
