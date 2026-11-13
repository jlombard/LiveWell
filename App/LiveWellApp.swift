import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications
import UIKit

@main
struct LiveWellApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppDelegate.model

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .onOpenURL { model.open($0) }
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active: Task { await model.sync() }
            case .background: AppDelegate.scheduleRefresh()
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.horizon") }.tag(AppTab.today)
            ReportView()
                .tabItem { Label("Report", systemImage: "newspaper") }.tag(AppTab.report)
            CheckinView()
                .tabItem { Label("Check-in", systemImage: "ruler") }.tag(AppTab.checkin)
        }
        .toolbarBackground(Theme.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

/// Runs on every launch, including when iOS wakes the app in the background for new Health data,
/// so the observers are always registered before Health delivers.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor static let model = AppModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppModel.refreshTaskID, using: nil) { task in
            Self.scheduleRefresh()
            let work = Task { @MainActor in
                await Self.model.sync()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        Task { @MainActor in Self.model.start() }
        return true
    }

    /// A periodic background refresh as a backstop for Health's own background delivery.
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppModel.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Tapping the Monday reminder opens straight to Check-in.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let link = response.notification.request.content.userInfo["link"] as? String, let url = URL(string: link) {
            await MainActor.run { Self.model.open(url) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
