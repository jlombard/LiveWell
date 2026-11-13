import SwiftUI
import LiveWellCore

/// The biweekly plan review, shown after "Commit to the week" every other week: two weeks of each
/// habit, each pillar's 4-week trend, and at most one proposed change to accept, defer or decline.
struct PlanReviewView: View {
    @Environment(AppModel.self) private var model
    var onDone: () -> Void
    @State private var review: ReviewData?
    @State private var reason = ""
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Plan review · every other week")
                Text("Two weeks in.").font(Theme.serif(34, relativeTo: .largeTitle)).foregroundStyle(Theme.text).padding(.top, 10)
                if let review {
                    Eyebrow("Habits · last two weeks").padding(.top, 26)
                    VStack(spacing: 0) { ForEach(review.habits, id: \.key) { habitRow($0) } }.padding(.top, 6)

                    Eyebrow("Progress · about four weeks").padding(.top, 26)
                    VStack(spacing: 0) { ForEach(review.pillars, id: \.key) { pillarRow($0) } }.padding(.top, 6)

                    proposalCard(review).padding(.top, 26)
                    Text("Tomorrow\u{2019}s Surf Report explains this, with sources.")
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 14)
                    if let problem { Text(problem).font(.footnote).foregroundStyle(.orange).padding(.top, 10) }
                }
            }
            .padding(20)
        }
        .onAppear { if review == nil { review = model.planReview() } }
        .transition(.opacity)
    }

    private func habitRow(_ habit: PlanReview.HabitWeeks) -> some View {
        HStack {
            Text(habit.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            Spacer()
            ForEach(Array(habit.weeks.enumerated()), id: \.offset) { _, value in
                let met = (value ?? -1) >= habit.goal
                Text(value.map(formatValue) ?? "\u{2013}")
                    .font(.body.monospacedDigit().weight(met ? .semibold : .regular))
                    .foregroundStyle(met ? Theme.accent : Theme.text)
                    .frame(width: 52, alignment: .trailing)
            }
            Text("of \(formatValue(habit.goal))").font(.footnote).foregroundStyle(Theme.secondary).frame(width: 56, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(habit.name): \(habit.weeks.map { $0.map(formatValue) ?? "not measured" }.joined(separator: ", then ")), goal \(formatValue(habit.goal))")
    }

    private func pillarRow(_ pillar: PlanReview.PillarTrend) -> some View {
        let word: String = {
            if pillar.to == nil { return "not measured" }
            switch pillar.trend {
            case .up: return "moving"
            case .flat: return "steady"
            case .down: return "slipped a little"
            case .unknown: return "not enough history yet"
            }
        }()
        return HStack {
            Text(pillar.label).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
            Spacer()
            if let from = pillar.from, let to = pillar.to {
                Text("\(formatValue(from)) → \(formatValue(to))").font(.body.monospacedDigit()).foregroundStyle(Theme.text)
            } else if let to = pillar.to {
                Text(formatValue(to)).font(.body.monospacedDigit()).foregroundStyle(Theme.text)
            }
            Text(pillar.reached ? "reached" : word).font(.footnote)
                .foregroundStyle(pillar.trend == .up || pillar.reached ? Theme.accent : Theme.secondary)
                .frame(width: 118, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func proposalCard(_ review: ReviewData) -> some View {
        let proposal = review.proposal
        return VStack(alignment: .leading, spacing: 12) {
            Eyebrow(proposal.isChange ? "One change to consider" : "No change proposed")
            Text(proposal.headline).font(Theme.serif(28, relativeTo: .title)).foregroundStyle(Theme.text)
            Text(proposal.reason).font(.subheadline).foregroundStyle(Theme.secondary)
            if proposal.isChange {
                TextField("Your reason (optional)", text: $reason, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                PrimaryButton(title: "Accept") { finish(review, "accept") }
                HStack(spacing: 8) {
                    Chip(title: "Not now", selected: false) { finish(review, "not_now") }
                    Chip(title: "No", selected: false) { finish(review, "no") }
                }
            } else {
                PrimaryButton(title: "Keep the plan") { finish(review, "stay") }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func finish(_ review: ReviewData, _ decision: String) {
        problem = model.decide(review, decision: decision, reason: reason)
        if problem == nil { onDone() }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { onDone() } }
    }
}
