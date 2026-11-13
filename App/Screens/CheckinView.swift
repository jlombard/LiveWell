import SwiftUI
import PhotosUI
import AudioToolbox
import UIKit
import SurfCore

/// Check-in: a hub, not a march. The goal leads; each measurement can be done any day this week.
struct CheckinView: View {
    @Environment(AppModel.self) private var model
    @State private var measuring: MeasurementDefinition?
    @State private var revealing: RevealContext?
    @State private var pendingReveal: RevealContext?
    @State private var closing = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage? = GoalPhoto.load()

    private var allDone: Bool {
        !model.config.measurements.isEmpty && model.config.measurements.allSatisfy { model.thisWeek($0.key) != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HorizonHeader()
                Eyebrow("This week\u{2019}s check-in").padding(.top, 20)
                goalCard.padding(.top, 14)

                if model.folderLinked {
                    Text("Measure each one when you\u{2019}re ready, any day this week.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 22)
                    VStack(spacing: 8) {
                        ForEach(model.config.measurements) { m in row(m) }
                    }
                    .padding(.top, 14)
                    if allDone {
                        PrimaryButton(title: "Close the week") { closing = true }.padding(.top, 16)
                    }
                    if model.settings.trialMode {
                        Text("Trial mode: check-ins are saved to health_app/checkins.csv, not the live file. Change this in Settings.")
                            .font(.caption).foregroundStyle(Theme.secondary).padding(.top, 14)
                    }
                } else {
                    Text("Link the Health Glance folder in Settings (the gear on Today) to save check-ins.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Theme.bg)
        .onAppear { model.loadCheckins() }
        .sheet(item: $measuring, onDismiss: { revealing = pendingReveal; pendingReveal = nil }) { m in
            MeasureSheet(measurement: m) { value in
                // Shown once the sheet has finished closing.
                pendingReveal = RevealContext(measurement: m, value: value,
                                          previous: model.checkins.previous(m.key, before: GoalMath.dayString(Date(), calendar: .current)))
            }
        }
        .fullScreenCover(item: $revealing) { RevealView(context: $0) }
        .fullScreenCover(isPresented: $closing) { CloseWeekView() }
        .onChange(of: photoItem) {
            Task {
                if let data = try? await photoItem?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    GoalPhoto.save(image)
                    photo = image
                }
            }
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photo == nil ? "Add your photo" : "Change photo", systemImage: "photo")
                        .font(.caption).foregroundStyle(Theme.text)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(.black.opacity(0.35), in: Capsule())
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                }
            }
            Text(model.config.goal.eventName)
                .font(Theme.serif(52, relativeTo: .largeTitle)).foregroundStyle(Theme.text).padding(.top, 30)
            Text("\(longDate(model.config.goal.targetDate)) · \(model.config.goal.eventLine)")
                .font(Theme.serif(19, relativeTo: .body, italic: true)).foregroundStyle(photo == nil ? Theme.secondary : Theme.text).padding(.top, 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.secondary.opacity(0.5)).frame(height: 1)
                    Rectangle().fill(Theme.accent).frame(width: geo.size.width * model.horizon, height: 1)
                    Circle().fill(Theme.text).frame(width: 9, height: 9).offset(x: geo.size.width * model.horizon - 4)
                    Circle().fill(Theme.accent).frame(width: 13, height: 13).offset(x: geo.size.width - 11)
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            .padding(.top, 30)
            .accessibilityHidden(true)
            HStack {
                Text("You, today")
                Spacer()
                if let days = model.daysLeft { Text("\(days) days to the water") }
            }
            .font(.caption).foregroundStyle(photo == nil ? Theme.secondary : Theme.text).padding(.top, 4)
        }
        .padding(EdgeInsets(top: 14, leading: 22, bottom: 22, trailing: 22))
        .background {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill().overlay(Color.black.opacity(0.5))
            } else {
                Theme.card
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.line, lineWidth: 1))
    }

    private func row(_ m: MeasurementDefinition) -> some View {
        let reading = model.thisWeek(m.key)
        return Button { measuring = m } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(reading == nil ? Theme.secondary.opacity(0.6) : Color.clear, lineWidth: 1.5)
                    if reading != nil {
                        Circle().fill(Theme.accent)
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.bg)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(reading.map { "Measured \(shortDay($0.date))" } ?? m.hint).font(.footnote).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if let reading { Text(formatValue(reading.value)).font(Theme.serif(24, relativeTo: .title2)).foregroundStyle(Theme.text) }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reading.map { "\(m.name), \(formatValue($0.value)), measured \(shortDay($0.date))" } ?? "\(m.name), not measured this week. \(m.hint)")
    }

    private func longDate(_ day: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: day) else { return day }
        return date.formatted(date: .long, time: .omitted)
    }
}

/// The optional goal photo: added by the person, kept on the phone only.
enum GoalPhoto {
    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("goal-photo.jpg")
    }
    static func load() -> UIImage? { UIImage(contentsOfFile: url.path) }
    static func save(_ image: UIImage) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? image.jpegData(compressionQuality: 0.85)?.write(to: url, options: .atomic)
    }
}

struct RevealContext: Identifiable {
    let id = UUID()
    let measurement: MeasurementDefinition
    let value: Double
    let previous: (date: String, value: Double)?
}

// MARK: - measuring

struct MeasureSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let measurement: MeasurementDefinition
    let onSaved: (Double) -> Void

    @State private var value: Double = 0
    @State private var error: String?
    // Timed count (pop-ups)
    @State private var phase: Phase = .ready
    @State private var remaining = 0
    @State private var timer: Task<Void, Never>?

    enum Phase { case ready, running, finished }

    private var last: (date: String, value: Double)? {
        model.checkins.previous(measurement.key, before: GoalMath.dayString(Date(), calendar: .current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(measurement.name).font(Theme.serif(28)).foregroundStyle(Theme.text)
                Spacer()
                Button("Cancel") { timer?.cancel(); dismiss() }.foregroundStyle(Theme.secondary).frame(minHeight: 44)
            }
            Text(last.map { "Last time: \(formatValue($0.value)) on \(shortDay($0.date))" } ?? "First measurement")
                .font(.subheadline).foregroundStyle(Theme.secondary)

            Spacer(minLength: 12)
            if measurement.entry == .timedCount { timedCount } else { stepper }
            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(measurement.protocolLine).foregroundStyle(Theme.text)
                Text(measurement.honestLabel).foregroundStyle(Theme.secondary)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))

            if let error { Text(error).font(.footnote).foregroundStyle(Theme.secondary).padding(.top, 8) }

            if measurement.entry == .stepper || phase == .finished {
                PrimaryButton(title: "Save") { save() }.padding(.top, 16)
            }
        }
        .padding(20)
        .background(Theme.card)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(phase == .running)
        .onAppear {
            let today = model.thisWeek(measurement.key)?.value
            value = measurement.entry == .timedCount ? 0 : (today ?? last?.value ?? (measurement.lowerIsBetter ? measurement.max : measurement.min))
            remaining = measurement.timerSeconds
        }
        .onDisappear { timer?.cancel() }
    }

    private var stepper: some View {
        HStack {
            stepButton("minus", label: "Less") { value = max(measurement.min, value - measurement.step) }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatValue(value)).font(Theme.serif(84, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                if !measurement.unit.isEmpty { Text(measurement.unit).font(.title3).foregroundStyle(Theme.secondary) }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            stepButton("plus", label: "More") { value = min(measurement.max, value + measurement.step) }
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2.weight(.medium)).foregroundStyle(Theme.text)
                .frame(width: 64, height: 64)
                .background(Theme.cardDeep, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var timedCount: some View {
        switch phase {
        case .ready:
            VStack(spacing: 16) {
                Text("\(measurement.timerSeconds) seconds. Tap the screen for each one.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                PrimaryButton(title: "Start") { startTimer() }
            }
        case .running:
            Button { value += 1; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() } label: {
                VStack(spacing: 4) {
                    Text("\(Int(value))").font(Theme.serif(120, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                    Text("\(remaining) s left · tap for each one").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.accent, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Count one. \(Int(value)) so far, \(remaining) seconds left")
        case .finished:
            VStack(spacing: 8) {
                stepper
                Text("Adjust if a tap was missed.").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func startTimer() {
        value = 0
        remaining = measurement.timerSeconds
        phase = .running
        signal(start: true)
        let end = Date().addingTimeInterval(Double(measurement.timerSeconds))
        timer = Task {
            while !Task.isCancelled {
                let left = end.timeIntervalSinceNow
                if left <= 0 { break }
                remaining = Int(left.rounded(.up))
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            remaining = 0
            phase = .finished
            signal(start: false)
        }
    }

    /// A haptic and a sound at the start and at the end.
    private func signal(start: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(start ? .warning : .success)
        AudioServicesPlaySystemSound(start ? 1113 : 1114)
    }

    private func save() {
        do {
            try model.saveMeasurement(measurement, value: value)
            dismiss()
            onSaved(value)
        } catch {
            self.error = "Couldn\u{2019}t save: \(error.localizedDescription)"
        }
    }
}

// MARK: - reveal

/// The number, then what it means. If it moved, the habits beside it with real counts.
/// If not, the recent trend, stated plainly.
struct RevealView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: RevealContext
    @State private var progress: Double = 0

    private var m: MeasurementDefinition { context.measurement }
    private var pillar: DashboardData.Pillar? { model.dashboard?.pillars.first { $0.key == m.pillar } }
    private var history: [(date: String, value: Double)] { model.checkins.history(m.key) }
    private var reveal: Reveal {
        Reveal.make(measurement: m, value: context.value, previous: context.previous, baseline: history.first)
    }

    private func fraction(_ value: Double) -> Double? {
        guard let from = pillar?.from, let goal = pillar?.goal, goal != from else { return nil }
        return min(1, max(0, (value - from) / (goal - from)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(m.name)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatValue(context.value)).font(Theme.serif(96, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
                if !m.unit.isEmpty { Text(m.unit).font(.title3).foregroundStyle(Theme.secondary) }
            }
            .padding(.top, 40)
            Text(reveal.headline).font(.body).foregroundStyle(Theme.text).padding(.top, 8)

            if fraction(context.value) != nil {
                ProgressLine(progress: progress, reached: false).padding(.top, 30)
                HStack {
                    Text((pillar?.from_label ?? "") + " start")
                    Spacer()
                    Text((pillar?.goal_label ?? "") + " goal")
                }
                .font(.caption).foregroundStyle(Theme.secondary).padding(.top, 4)
            }

            if reveal.kind == .improved {
                Eyebrow("What you put in").padding(.top, 36)
                ForEach(m.relatedHabits, id: \.self) { key in
                    if let status = model.status(key), let value = status.value { habitRow(status, value) }
                }
            } else if history.count >= 2 {
                Eyebrow("Last \(min(4, history.count)) readings").padding(.top, 36)
                HStack(spacing: 8) {
                    ForEach(Array(history.suffix(4).enumerated()), id: \.offset) { _, reading in
                        VStack(spacing: 2) {
                            Text(formatValue(reading.value)).font(Theme.serif(24, relativeTo: .title2)).foregroundStyle(Theme.text)
                            Text(shortDay(reading.date)).font(.caption2).foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.top, 12)
            }

            Spacer()
            Text(m.honestLabel).font(.footnote).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
            PrimaryButton(title: "Done") { dismiss() }.padding(.top, 18)
        }
        .padding(EdgeInsets(top: 40, leading: 24, bottom: 24, trailing: 24))
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            let target = fraction(context.value) ?? 0
            progress = fraction(context.previous?.value ?? context.value) ?? 0
            if reduceMotion { progress = target }
            else { withAnimation(.spring(duration: 1.4, bounce: 0.1).delay(0.4)) { progress = target } }
            if reveal.kind == .improved { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    private func habitRow(_ status: HabitStatus, _ value: Double) -> some View {
        HStack(spacing: 14) {
            Image(systemName: HabitSymbol.name(status.key)).foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36).background(Theme.accent.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(status.goal >= 100 ? "\(Int(value)) \(status.name.lowercased()) minutes" : "\(Int(value)) of \(Int(status.goal)) \(status.name.lowercased())")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("Last \(model.config.habitWindowDays) days").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 10)
    }
}

// MARK: - closing the week

/// Tap each habit to commit. All lit: "Committed."
struct CloseWeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var committed: Set<String> = []
    @State private var reflection = ""
    @State private var done = false

    private let prompt = "What feels easier lately?"
    /// Asked about one week in four, never required.
    private var askReflection: Bool { Calendar.current.component(.weekOfYear, from: Date()) % 4 == 0 }
    private var allOn: Bool { committed.count == model.config.habits.count }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if done { finished } else { choosing }
        }
        .preferredColorScheme(.dark)
    }

    private var choosing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Eyebrow("Check-in complete")
                    Spacer()
                    Button("Not now") { dismiss() }.foregroundStyle(Theme.secondary).frame(minHeight: 44)
                }
                HStack(spacing: 8) {
                    ForEach(model.config.measurements) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1)
                            Text(model.thisWeek(m.key).map { formatValue($0.value) } ?? "\u{2013}")
                                .font(Theme.serif(24, relativeTo: .title2)).foregroundStyle(Theme.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.top, 4)

                Text("Commit to the week.").font(Theme.serif(34, relativeTo: .largeTitle)).foregroundStyle(Theme.text).padding(.top, 30)
                Text("Tap each habit to commit. Every one of them moves a bar.")
                    .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 8)

                VStack(spacing: 8) {
                    ForEach(model.config.habits) { habit in commitRow(habit) }
                }
                .padding(.top, 18)

                if askReflection {
                    Text(prompt).font(Theme.serif(22, relativeTo: .title3)).foregroundStyle(Theme.text).padding(.top, 28)
                    TextField("Optional", text: $reflection, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(Theme.cardDeep, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 10)
                }

                if allOn {
                    PrimaryButton(title: "Commit") {
                        model.commitWeek(habits: Array(committed), reflection: askReflection ? reflection : nil, prompt: prompt)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation(.easeInOut(duration: 0.8)) { done = true }
                    }
                    .padding(.top, 20)
                }
            }
            .padding(20)
        }
    }

    private func commitRow(_ habit: HabitDefinition) -> some View {
        let on = committed.contains(habit.key)
        let target = habit.goal >= 100 ? "\(Int(habit.goal)) minutes" : "\(Int(habit.goal)) \(habit.goal == 1 ? "time" : "times")"
        let pillars = habit.pillars.map { key in model.dashboard?.pillars.first { $0.key == key }?.label ?? key.capitalized }
        return Button {
            if on { committed.remove(habit.key) } else { committed.insert(habit.key); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(on ? Color.clear : Theme.secondary.opacity(0.6), lineWidth: 1.5)
                    if on {
                        Circle().fill(Theme.accent)
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Theme.bg)
                    }
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name).font(.body.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(target).font(.footnote).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(pillars.joined(separator: " · ")).font(.caption).foregroundStyle(on ? Theme.accent : Theme.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(on ? Theme.accent.opacity(0.10) : Theme.cardDeep, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(habit.name), \(target), moves \(pillars.joined(separator: " and "))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var finished: some View {
        VStack(spacing: 0) {
            Text("Committed.").font(Theme.serif(56, relativeTo: .largeTitle)).foregroundStyle(Theme.text)
            Text("\(spelled(model.config.habits.count)) habits. One goal.").font(.body).foregroundStyle(Theme.secondary).padding(.top, 14)
            Rectangle().fill(Theme.accent).frame(width: 120, height: 1).padding(.top, 40)
            if let days = model.daysLeft {
                Text("\(days) days to the water.").font(Theme.serif(22, relativeTo: .title3, italic: true)).foregroundStyle(Theme.text).padding(.top, 18)
            }
            if let behind = HabitCounter.furthestBehind(model.statuses) {
                Text("\(behind.name) is the quiet one right now, so it leads your widget.")
                    .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 260).padding(.top, 28)
            }
            Button("Back to Today") { model.tab = .today; dismiss() }
                .foregroundStyle(Theme.text).frame(minHeight: 44).padding(.top, 40)
        }
        .padding(32)
        .transition(.opacity)
    }

    private func spelled(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .spellOut
        return (f.string(from: NSNumber(value: n)) ?? "\(n)").capitalized
    }
}
