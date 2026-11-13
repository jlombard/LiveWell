import SwiftUI
import UniformTypeIdentifiers
import LiveWellCore

/// Settings behind the gear on Today: the folder, Health, the plan as configuration, and sync status.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pickingFolder = false
    @State private var newActivity = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Health Glance folder", value: model.folder.displayName)
                    Button(model.folderLinked ? "Choose a different folder" : "Choose folder") { pickingFolder = true }
                    Toggle("Trial mode", isOn: $model.settings.trialMode)
                } header: { Text("Folder") } footer: {
                    Text(model.settings.trialMode
                         ? "Writing to health_app/ so you can compare with the Shortcuts' files. Nothing the Mac reads is touched."
                         : "Writing the live files in health/ and checkins.csv. Turn the Export Shortcut, the Watch automations and the Monday Shortcut off.")
                }

                Section {
                    Button(model.health.hasRequested ? "Review Health access" : "Connect Apple Health") {
                        Task { await model.connectHealth() }
                    }
                } header: { Text("Apple Health") } footer: {
                    Text("Reads workouts, Exercise minutes, VO\u{2082} max, weight and sleep. Saves a workout only when you log one on Today. Nothing leaves your phone except the files in your own iCloud folder.")
                }

                Section("Monday check-in reminder") {
                    Toggle("Remind me", isOn: $model.settings.reminderOn)
                    if model.settings.reminderOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    ForEach($model.config.habits) { $habit in
                        Stepper(value: $habit.goal, in: 1...1000, step: habit.goal >= 100 ? 10 : 1) {
                            LabeledContent(habit.name, value: "\(Int(habit.goal))")
                        }
                    }
                } header: { Text("Habit goals") } footer: {
                    Text("Counted over the last \(model.config.habitWindowDays) days, the same as the Mac dashboard.")
                }

                Section {
                    ForEach(model.config.workoutTypeMap.keys.sorted(), id: \.self) { activity in
                        LabeledContent(activity) {
                            TextField("type", text: mapBinding(activity))
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .onDelete { offsets in
                        let keys = model.config.workoutTypeMap.keys.sorted()
                        for i in offsets { model.config.workoutTypeMap[keys[i]] = nil }
                    }
                    Picker("Add a workout type", selection: $newActivity) {
                        Text("Choose").tag("")
                        ForEach(ActivityNames.all.filter { model.config.workoutTypeMap[$0] == nil }, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: newActivity) {
                        guard !newActivity.isEmpty else { return }
                        model.config.workoutTypeMap[newActivity] = "strength"
                        newActivity = ""
                    }
                } header: { Text("Which workouts count as what") } footer: {
                    Text("Apple Health workout type on the left; what it is written as on the right. Lift counts \u{201C}strength\u{201D}, Row counts \u{201C}rowing\u{201D}, Yoga counts \u{201C}yoga\u{201D}. Anything not listed is written under its own name.")
                }

                Section {
                    if model.fileStatus.isEmpty { Text("Nothing written yet").foregroundStyle(.secondary) }
                    ForEach(model.fileStatus.keys.sorted(), id: \.self) { path in
                        if let status = model.fileStatus[path] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(path).font(.subheadline.monospaced())
                                Text(status.lastWrite.map { "Written \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not written yet")
                                    .font(.footnote).foregroundStyle(.secondary)
                                if let error = status.lastError {
                                    Text(error).font(.footnote).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    Button(model.isSyncing ? "Syncing\u{2026}" : "Sync now") { Task { await model.sync() } }
                        .disabled(model.isSyncing)
                    Button("Rebuild from Health") { Task { await model.rebuildFromHealth() } }
                        .disabled(model.isSyncing)
                } header: { Text("Sync") } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let last = model.lastSync { Text("Health last read \(last.formatted(date: .abbreviated, time: .shortened)).") }
                        if let generated = model.dashboard?.generated { Text("data.json from the Mac: \(generated.replacingOccurrences(of: "T", with: " ")).") }
                        if let error = model.syncError { Text(error) }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.linkFolder(url) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: model.settings.reminderHour, minute: model.settings.reminderMinute)) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings.reminderHour = c.hour ?? 7
            model.settings.reminderMinute = c.minute ?? 0
        }
    }

    private func mapBinding(_ activity: String) -> Binding<String> {
        Binding { model.config.workoutTypeMap[activity] ?? "" } set: { model.config.workoutTypeMap[activity] = $0 }
    }
}

/// Report tab. The Surf Report arrives in Phase 2; until then this says so plainly.
struct ReportView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HorizonHeader()
            Text("The Surf Report").font(Theme.serif(40, relativeTo: .largeTitle)).foregroundStyle(Theme.text).padding(.top, 24)
            Text("Reading the Report here is Phase 2. For now it stays on its web page, written each morning as usual.")
                .font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 10)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
    }
}
