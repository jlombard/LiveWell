import SwiftUI
import UniformTypeIdentifiers
import LiveWellCore

/// Settings behind the gear on Today: the folder, Health, the plan as configuration, and sync status.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pickingFolder = false
    @State private var newActivity = ""
    @State private var keyDraft = ""
    @State private var hasKey = Keychain.apiKey != nil
    @State private var pickingHoldings = false
    @State private var finnhubDraft = ""
    @State private var hasFinnhub = Keychain.finnhubKey != nil

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
                         ? "Writing to health_app/ so you can compare with the Shortcuts' files; the live files in health/ and checkins.csv aren't touched. Food check-ins made here still count: the morning run folds them in."
                         : "Writing the live files in health/ (including plan_days.csv) and checkins.csv. Turn the Export Shortcut, the Watch automations and the Monday Shortcut off, and do the food check-in here, not on the web page. "
                         + (model.cutoverNote ?? "Turning trial mode off moves health/workouts_log.csv to health/old/."))
                }

                Section {
                    Button(model.health.hasRequested ? "Review Health access" : "Connect Apple Health") {
                        Task { await model.connectHealth() }
                    }
                } header: { Text("Apple Health") } footer: {
                    Text("Reads workouts, Exercise minutes, VO\u{2082} max, weight and sleep. Saves a workout only when you log one on Today. Nothing leaves your phone except the files in your own iCloud folder.")
                }

                Section {
                    if hasKey {
                        LabeledContent("API key", value: "Saved on this phone")
                        Button("Remove key", role: .destructive) { Keychain.apiKey = nil; hasKey = false }
                    } else {
                        SecureField("Anthropic API key", text: $keyDraft)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Save key") { Keychain.apiKey = keyDraft; keyDraft = ""; hasKey = Keychain.apiKey != nil }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Picker("Model", selection: $model.settings.chatModel) {
                        ForEach(ClaudeClient.models, id: \.id) { Text($0.name).tag($0.id) }
                    }
                } header: { Text("Go deeper chat") } footer: {
                    Text("Questions you ask on a Surf Report card go from this phone straight to Anthropic, billed to your API account. The key is kept in the iOS Keychain and never written to the Health Glance folder.")
                }

                Section {
                    LabeledContent("Holdings", value: model.wealth.holdings.isEmpty ? "None imported"
                                   : "\(model.wealth.holdings.count) · \(model.wealth.importedOn.map(shortDay) ?? "")")
                    Button(model.wealth.holdings.isEmpty ? "Import holdings CSV" : "Import a newer CSV") { pickingHoldings = true }
                    if hasFinnhub {
                        LabeledContent("Finnhub key", value: "Saved on this phone")
                        Button("Remove key", role: .destructive) { Keychain.finnhubKey = nil; hasFinnhub = false }
                    } else {
                        SecureField("Finnhub API key", text: $finnhubDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Save key") {
                            Keychain.finnhubKey = finnhubDraft; finnhubDraft = ""; hasFinnhub = Keychain.finnhubKey != nil
                            Task { await model.wealth.refresh(force: true) }
                        }
                        .disabled(finnhubDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Toggle("Show the day, not the week", isOn: $model.settings.wealthDaily)
                    if hasFinnhub, !model.wealth.holdings.isEmpty {
                        Button(model.wealth.isRefreshing ? "Checking\u{2026}" : "Check prices now") { Task { await model.wealth.refresh(force: true) } }
                            .disabled(model.wealth.isRefreshing)
                    }
                    if !model.wealth.holdings.isEmpty {
                        Button("Remove holdings and prices", role: .destructive) { model.wealth.clear() }
                    }
                } header: { Text("Wealth") } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export positions from your brokerage as a CSV and import it here, or share the file to LiveWell. Only the ticker, shares, cost basis and security name are kept, on this phone. The Health Glance folder gets each holding\u{2019}s share of the account in percent, never share counts or dollar amounts.")
                        if let day = model.wealth.book.latestDay { Text("Closing prices through \(shortDay(day)). Checked once after each US close.") }
                        if let note = model.wealth.note { Text(note).foregroundStyle(.orange) }
                    }
                }

                Section {
                    Toggle("New issue alert", isOn: $model.settings.issueAlerts)
                } header: { Text("The Surf Report") } footer: {
                    Text("A notification with the lead headline as soon as a new issue reaches the phone. iOS decides when background checks run, so it can arrive a little after the morning run finishes.")
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
            .background {
                // A second importer has to hang off a different view than the folder picker.
                Color.clear.fileImporter(isPresented: $pickingHoldings, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                    if case .success(let url) = result { model.importHoldings(from: url) }
                }
            }
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
