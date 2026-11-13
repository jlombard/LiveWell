import SwiftUI
import UIKit
import SurfCore

/// Today: the one line for the day, five habit tiles (tap to log), five progress bars.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logging: HabitDefinition?
    @State private var showSettings = false
    @State private var planNote = false
    /// Bar positions on screen; start at the values last seen and glide to today's.
    @State private var shown: [String: Double] = [:]
    @State private var deltas: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HorizonHeader {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Theme.secondary).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }

                Text(model.todayLine)
                    .font(Theme.serif(34, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 24)

                if !model.folderLinked {
                    setupCard("Link your Health Glance folder", "So the app can write Health files for the Mac and read your progress back.") { showSettings = true }
                } else if !model.health.hasRequested {
                    setupCard("Connect Apple Health", "Workouts sync on their own, with no Shortcuts.") { Task { await model.connectHealth() } }
                }

                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("Last \(model.config.habitWindowDays) days")
                    Spacer()
                    Text("Tap to log").font(.caption).foregroundStyle(Theme.secondary)
                }
                .padding(.top, 26)

                HStack(spacing: 8) {
                    ForEach(model.statuses) { status in
                        HabitTile(status: status) { tap(status) }
                    }
                }
                .padding(.top, 10)

                if planNote {
                    Text("Food check-in moves into the app in Phase 2. Until then it stays on the Surf Report page.")
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 10)
                }

                Eyebrow("Progress").padding(.top, 26)

                if let pillars = model.dashboard?.pillars, !pillars.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(pillars) { pillar in
                            PillarRow(pillar: pillar,
                                      progress: shown[pillar.key] ?? pillar.progress ?? 0,
                                      delta: deltas[pillar.key],
                                      note: model.lastLogged?.pillar == pillar.key ? model.lastLogged?.text : nil)
                        }
                    }
                    .padding(.top, 6)
                    if let generated = model.dashboard?.generated {
                        Text("From the Mac · \(generated.replacingOccurrences(of: "T", with: " "))")
                            .font(.caption2).foregroundStyle(Theme.secondary).padding(.top, 12)
                    }
                } else {
                    Text("Not measured yet. Progress appears once the Mac has written data.json to the Health Glance folder.")
                        .font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 10)
                }

                if let error = model.syncError {
                    Text(error).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .refreshable { await model.sync() }
        .sheet(item: $logging) { habit in
            LogSheet(habit: habit).presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { glide(); celebrateNewlyMet() }
        .onChange(of: model.dashboard) { glide() }
        .onChange(of: model.statuses) { celebrateNewlyMet() }
    }

    private func setupCard(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Text(detail).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
    }

    private func tap(_ status: HabitStatus) {
        guard let habit = model.config.habit(status.key) else { return }
        if habit.logsAs != nil { logging = habit }
        else if case .planDays = habit.source { planNote.toggle() }
    }

    /// Each bar moves once from the value last seen to today's, staggered, under about 1.5 s.
    private func glide() {
        guard let pillars = model.dashboard?.pillars else { return }
        let defaults = UserDefaults.standard
        let seenProgress = defaults.dictionary(forKey: "seenProgress") as? [String: Double] ?? [:]
        let seenValue = defaults.dictionary(forKey: "seenValue") as? [String: Double] ?? [:]
        var newProgress: [String: Double] = [:], newValue: [String: Double] = [:], labels: [String: String] = [:]
        for pillar in pillars {
            guard let progress = pillar.progress, let value = pillar.value else { continue }
            newProgress[pillar.key] = progress
            newValue[pillar.key] = value
            if shown[pillar.key] == nil { shown[pillar.key] = seenProgress[pillar.key] ?? progress }
            if let old = seenValue[pillar.key], abs(value - old) >= 0.05 {
                labels[pillar.key] = (value > old ? "+" : "\u{2212}") + String(format: "%.1f", abs(value - old))
            }
        }
        defaults.set(newProgress, forKey: "seenProgress")
        defaults.set(newValue, forKey: "seenValue")
        if reduceMotion {
            shown = newProgress
        } else {
            for (i, pillar) in pillars.enumerated() {
                guard let target = newProgress[pillar.key] else { continue }
                withAnimation(.spring(duration: 1.1, bounce: 0.1).delay(0.2 + Double(i) * 0.08)) { shown[pillar.key] = target }
            }
        }
        guard !labels.isEmpty else { return }
        deltas = labels
        Task {
            try? await Task.sleep(for: .seconds(3.6))
            withAnimation(.easeOut(duration: 0.6)) { deltas = [:] }
        }
    }

    /// One light haptic the first time a met tile is seen that day.
    private func celebrateNewlyMet() {
        let key = "metSeen-" + GoalMath.dayString(Date(), calendar: .current)
        let seen = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let met = Set(model.statuses.filter(\.met).map(\.key))
        guard !met.subtracting(seen).isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UserDefaults.standard.set(Array(met.union(seen)), forKey: key)
    }
}

/// Icon, count and name only. A met tile fills with the accent.
struct HabitTile: View {
    let status: HabitStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: HabitSymbol.name(status.key))
                    .font(.system(size: 20))
                    .foregroundStyle(status.met ? Theme.accent : Theme.text)
                    .frame(height: 24)
                Group {
                    if let value = status.value {
                        if status.goal >= 100 {
                            Text("\(Int(value))")
                        } else {
                            Text("\(Int(value))") + Text("/\(Int(status.goal))").font(.caption).foregroundColor(Theme.secondary)
                        }
                    } else {
                        Text("\u{2013}")
                    }
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(status.name).font(.caption2).foregroundStyle(status.met ? Theme.text : Theme.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(status.met ? Theme.accent.opacity(0.14) : Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(status.met ? Theme.accent : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        guard let value = status.value else { return "\(status.name), not measured" }
        return "\(status.name), \(Int(value)) of \(Int(status.goal))" + (status.met ? ", met" : "")
    }
}

/// One pillar: name, what is measured, the current number, and the line from start to goal.
struct PillarRow: View {
    let pillar: DashboardData.Pillar
    let progress: Double
    let delta: String?
    let note: String?

    private var reached: Bool { pillar.reached ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(pillar.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if let desc = pillar.desc { Text(desc).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1) }
                if reached { Text("Reached").font(.caption.weight(.medium)).foregroundStyle(Theme.accent) }
                Spacer()
                if let delta { Text(delta).font(.caption).foregroundStyle(Theme.accent).transition(.opacity) }
                Text(pillar.value == nil ? "Not measured" : (pillar.display ?? ""))
                    .font(pillar.value == nil ? .caption : Theme.serif(26, relativeTo: .title2))
                    .foregroundStyle(pillar.value == nil ? Theme.secondary : Theme.text)
            }
            if pillar.value != nil {
                ProgressLine(progress: reached ? 1 : progress, reached: reached)
                HStack {
                    Text(pillar.from_label ?? "")
                    Spacer()
                    Text(pillar.goal_label ?? "")
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(Theme.text).padding(.top, 2).transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(note != nil ? Theme.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, -10)
        .animation(.easeInOut(duration: 0.5), value: note)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard pillar.value != nil else { return "\(pillar.label), not measured" }
        var text = "\(pillar.label), \(pillar.desc ?? ""), \(pillar.display ?? "")"
        if let goal = pillar.goal_label { text += ", goal \(goal)" }
        if reached { text += ", reached" }
        return text
    }
}

/// Log a lift, row or yoga session that just ended. Saves a real workout to Apple Health.
struct LogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let habit: HabitDefinition
    @State private var minutes = 30
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Log \(habit.name.lowercased())").font(Theme.serif(28)).foregroundStyle(Theme.text)
                Spacer()
                Button("Cancel") { dismiss() }.foregroundStyle(Theme.secondary).frame(minHeight: 44)
            }
            Text("Today · ended just now").font(.subheadline).foregroundStyle(Theme.secondary)
            Eyebrow("How long").padding(.top, 22)
            HStack(spacing: 8) {
                ForEach([15, 20, 30, 45], id: \.self) { m in
                    Chip(title: "\(m) min", selected: minutes == m) { minutes = m }
                }
            }
            .padding(.top, 10)
            Text("\(habit.why) Saved to Apple Health as a workout.")
                .font(.footnote).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 22)
            Spacer(minLength: 16)
            PrimaryButton(title: saving ? "Saving\u{2026}" : "Save") {
                guard !saving else { return }
                saving = true
                Task {
                    await model.log(habit, minutes: minutes)
                    dismiss()
                }
            }
        }
        .padding(20)
        .background(Theme.card)
        .preferredColorScheme(.dark)
    }
}
