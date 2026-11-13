import Foundation
import HealthKit
import SwiftData
import SurfCore

/// Reads Apple Health into the app's store. Workouts, VO2 max and weight are fetched
/// incrementally by anchor (adds, edits and deletions); Exercise minutes and sleep are re-read
/// for a recent window on every sync.
@MainActor
final class HealthSync {
    let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let workoutType = HKObjectType.workoutType()
    private let vo2Type = HKQuantityType(.vo2Max)
    private let weightType = HKQuantityType(.bodyMass)
    private let exerciseType = HKQuantityType(.appleExerciseTime)
    private let sleepType = HKCategoryType(.sleepAnalysis)

    private var readTypes: Set<HKObjectType> { [workoutType, vo2Type, weightType, exerciseType, sleepType] }

    struct Pull {
        var exerciseMinutes: [DatedValue]?
        var sleep: [SleepRow]
        var changedWorkouts: Bool
    }

    enum SyncError: LocalizedError {
        case locked
        case unavailable
        var errorDescription: String? {
            switch self {
            case .locked: return "Health is locked while the phone is locked. It will retry at the next unlock."
            case .unavailable: return "Health data isn't available on this device."
            }
        }
    }

    // MARK: permission

    /// Asks to read the five types and to save workouts (for tap-to-log on Today).
    func requestAccess() async throws {
        guard Self.isAvailable else { throw SyncError.unavailable }
        try await store.requestAuthorization(toShare: [workoutType], read: readTypes)
        UserDefaults.standard.set(true, forKey: "healthRequested")
    }

    var hasRequested: Bool { UserDefaults.standard.bool(forKey: "healthRequested") }

    // MARK: staying current

    /// Call at every launch (including background launches): registers observers and background
    /// delivery. `onChange` runs a sync; Health is told the update was handled when it returns.
    func startObserving(onChange: @escaping @MainActor () async -> Void) {
        guard Self.isAvailable, hasRequested, observers.isEmpty else { return }
        let plan: [(HKSampleType, HKUpdateFrequency)] = [
            (workoutType, .immediate), (vo2Type, .hourly), (weightType, .hourly),
            (exerciseType, .hourly), (sleepType, .hourly),
        ]
        for (type, frequency) in plan {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task { @MainActor in
                    await onChange()
                    completion()
                }
            }
            store.execute(query)
            observers.append(query)
            store.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }

    // MARK: pulling

    func pull(into context: ModelContext, exerciseDays: Int, sleepDays: Int) async throws -> Pull {
        guard Self.isAvailable else { throw SyncError.unavailable }
        do {
            let changed = try await pullWorkouts(into: context)
            try await pullReadings(type: vo2Type, kind: "vo2max", into: context)
            try await pullReadings(type: weightType, kind: "weight", into: context)
            let minutes = try await exerciseMinutes(days: exerciseDays)
            let sleep = try await sleepRows(days: sleepDays)
            return Pull(exerciseMinutes: minutes, sleep: sleep, changedWorkouts: changed)
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            throw SyncError.locked
        }
    }

    private func anchor(_ key: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: "anchor." + key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, _ key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: "anchor." + key)
        }
    }

    /// Forget the anchors so the next sync re-reads full history (used by "Rebuild from Health").
    func resetAnchors() {
        for key in ["workouts", "vo2max", "weight"] { UserDefaults.standard.removeObject(forKey: "anchor." + key) }
    }

    private func pullWorkouts(into context: ModelContext) async throws -> Bool {
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.workout()], anchor: anchor("workouts"))
        let result = try await descriptor.result(for: store)
        let ownBundle = Bundle.main.bundleIdentifier
        for workout in result.addedSamples {
            let uuid = workout.uuid
            let existing = try context.fetch(FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.uuid == uuid })).first
            let manual = workout.sourceRevision.source.bundleIdentifier == ownBundle
                || (workout.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
            let entry = existing ?? WorkoutEntry(uuid: uuid, activity: "", start: .now, end: .now, minutes: 0, sourceName: "", provenance: "")
            entry.activity = ActivityNames.name(workout.workoutActivityType)
            entry.start = workout.startDate
            entry.end = workout.endDate
            entry.minutes = workout.duration / 60
            entry.sourceName = workout.sourceRevision.source.name
            entry.provenance = (manual ? Provenance.manual : Provenance.measured).rawValue
            if existing == nil { context.insert(entry) }
        }
        for deleted in result.deletedObjects {
            let uuid = deleted.uuid
            for entry in try context.fetch(FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.uuid == uuid })) {
                context.delete(entry)
            }
        }
        try context.save()
        saveAnchor(result.newAnchor, "workouts")
        return !result.addedSamples.isEmpty || !result.deletedObjects.isEmpty
    }

    private func pullReadings(type: HKQuantityType, kind: String, into context: ModelContext) async throws {
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.quantitySample(type: type)], anchor: anchor(kind))
        let result = try await descriptor.result(for: store)
        let unit: HKUnit = kind == "weight"
            ? .pound()
            : HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        for sample in result.addedSamples {
            let uuid = sample.uuid
            let existing = try context.fetch(FetchDescriptor<HealthReading>(predicate: #Predicate { $0.uuid == uuid })).first
            let entered = (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true
            let provenance: Provenance = kind == "vo2max" ? .estimated : (entered ? .manual : .measured)
            let reading = existing ?? HealthReading(uuid: uuid, kind: kind, date: .now, value: 0, provenance: "")
            reading.date = sample.startDate
            reading.value = sample.quantity.doubleValue(for: unit)
            reading.provenance = provenance.rawValue
            if existing == nil { context.insert(reading) }
        }
        for deleted in result.deletedObjects {
            let uuid = deleted.uuid
            for reading in try context.fetch(FetchDescriptor<HealthReading>(predicate: #Predicate { $0.uuid == uuid })) {
                context.delete(reading)
            }
        }
        try context.save()
        saveAnchor(result.newAnchor, kind)
    }

    /// Apple Exercise minutes per local day. nil when Health returned nothing at all
    /// (no access, or no Watch), so the app shows "not measured" instead of zero.
    private func exerciseMinutes(days: Int) async throws -> [DatedValue]? {
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) else { return nil }
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: exerciseType, predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)
        var rows: [DatedValue] = []
        collection.enumerateStatistics(from: start, to: now) { statistics, _ in
            if let sum = statistics.sumQuantity() {
                rows.append(DatedValue(date: statistics.startDate, value: sum.doubleValue(for: .minute())))
            }
        }
        return rows.isEmpty ? nil : rows
    }

    private func sleepRows(days: Int) async throws -> [SleepRow] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)
        return samples.compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: String
            switch value {
            case .inBed: stage = "In bed"
            case .awake: stage = "Awake"
            case .asleepCore: stage = "Core"
            case .asleepDeep: stage = "Deep"
            case .asleepREM: stage = "REM"
            case .asleepUnspecified: stage = "Asleep"
            @unknown default: stage = "Asleep"
            }
            return SleepRow(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    // MARK: tap-to-log

    /// Saves a real workout to Apple Health that ended now. The observer then brings it back
    /// into the store like any other workout, so it is counted exactly once.
    func logWorkout(activity: String, minutes: Int) async throws {
        guard Self.isAvailable else { throw SyncError.unavailable }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = ActivityNames.type(activity)
        let end = Date()
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}

/// Names for HealthKit workout types, as used in the config's workout map.
enum ActivityNames {
    private static let table: [(HKWorkoutActivityType, String)] = [
        (.yoga, "yoga"), (.rowing, "rowing"),
        (.traditionalStrengthTraining, "traditionalStrengthTraining"),
        (.functionalStrengthTraining, "functionalStrengthTraining"),
        (.walking, "walking"), (.hiking, "hiking"), (.running, "running"), (.cycling, "cycling"),
        (.swimming, "swimming"), (.surfingSports, "surfingSports"), (.pilates, "pilates"),
        (.highIntensityIntervalTraining, "highIntensityIntervalTraining"), (.coreTraining, "coreTraining"),
        (.flexibility, "flexibility"), (.cooldown, "cooldown"), (.mindAndBody, "mindAndBody"),
        (.elliptical, "elliptical"), (.stairClimbing, "stairClimbing"), (.stairs, "stairs"),
        (.mixedCardio, "mixedCardio"), (.crossTraining, "crossTraining"), (.dance, "dance"),
        (.cardioDance, "cardioDance"), (.golf, "golf"), (.tennis, "tennis"), (.pickleball, "pickleball"),
        (.paddleSports, "paddleSports"), (.waterFitness, "waterFitness"), (.downhillSkiing, "downhillSkiing"),
        (.snowboarding, "snowboarding"), (.crossCountrySkiing, "crossCountrySkiing"), (.taiChi, "taiChi"),
        (.barre, "barre"), (.kickboxing, "kickboxing"), (.boxing, "boxing"), (.climbing, "climbing"),
        (.jumpRope, "jumpRope"), (.stepTraining, "stepTraining"), (.other, "other"),
    ]

    static func name(_ type: HKWorkoutActivityType) -> String {
        table.first { $0.0 == type }?.1 ?? "other"
    }

    static func type(_ name: String) -> HKWorkoutActivityType {
        table.first { $0.1 == name }?.0 ?? .other
    }

    static var all: [String] { table.map(\.1).sorted() }
}
