import AppKit
import Observation
import Sparkle
import UserNotifications

@MainActor
@Observable
final class UpdateService {
    private(set) var canCheckForUpdates = false
    private(set) var availableVersion: String?
    private(set) var lastCheckedAt: Date?
    private(set) var statusMessage: String?
    private(set) var notificationsEnabled: Bool
    private(set) var requestingNotificationPermission = false
    var automaticallyChecksForUpdates = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let delegate = UpdateDelegate()
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private let defaults: UserDefaults

    nonisolated static let notificationID = "WorldClockUpdate"
    var isConfigured: Bool { controller != nil }
    var canPresentUpdate: Bool { canCheckForUpdates || availableVersion != nil }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notificationsEnabled = defaults.bool(forKey: "updateNotificationsEnabled")
    }

    func start(bundle: Bundle = .main) {
        guard controller == nil else { return }
        guard Self.hasValidConfiguration(bundle.infoDictionary ?? [:]) else {
            statusMessage = "This build is not configured for updates. Use the signed release in Applications to check for updates."
            return
        }
        delegate.service = self
        UNUserNotificationCenter.current().delegate = delegate
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: delegate
        )
        do {
            try controller.updater.start()
            self.controller = controller
            automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
            lastCheckedAt = controller.updater.lastUpdateCheckDate
            observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
                [weak self] updater, _ in
                Task { @MainActor in self?.canCheckForUpdates = updater.canCheckForUpdates }
            }
        } catch {
            statusMessage = "Could not start updates: \(error.localizedDescription)"
        }
    }

    static func hasValidConfiguration(_ info: [String: Any]) -> Bool {
        guard let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil
        else { return false }
        return true
    }

    func checkForUpdates() {
        guard canPresentUpdate else { return }
        clearNotification()
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        guard !requestingNotificationPermission else { return }
        if enabled {
            requestingNotificationPermission = true
            defer { requestingNotificationPermission = false }
            do {
                notificationsEnabled = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert])
                statusMessage = notificationsEnabled ? nil : "Allow WorldClock notifications in System Settings to receive update alerts."
            } catch {
                notificationsEnabled = false
                statusMessage = "Could not enable notifications: \(error.localizedDescription)"
            }
        } else {
            notificationsEnabled = false
            clearNotification()
        }
        defaults.set(notificationsEnabled, forKey: "updateNotificationsEnabled")
    }

    fileprivate func presentReminder(version: String) {
        availableVersion = version
        guard notificationsEnabled,
              defaults.string(forKey: "lastNotifiedUpdateVersion") != version else { return }
        let content = UNMutableNotificationContent()
        content.title = "WorldClock \(version) is available"
        content.body = "Click to review the update."
        let request = UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                defaults.set(version, forKey: "lastNotifiedUpdateVersion")
            } catch {
                // The menu reminder remains available even if macOS declines the notification.
                statusMessage = "An update is available. macOS could not deliver its notification."
            }
        }
    }

    fileprivate func finishCheck() {
        lastCheckedAt = controller?.updater.lastUpdateCheckDate
    }

    fileprivate func finishSession() {
        availableVersion = nil
        clearNotification()
        NSApp.setActivationPolicy(.accessory)
    }

    fileprivate func clearNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.notificationID])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }
}

private final class UpdateDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate,
    UNUserNotificationCenterDelegate {
    weak var service: UpdateService?

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false // Our menu reminder presents scheduled updates without taking focus.
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            if state.userInitiated {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
            } else {
                service?.presentReminder(version: update.displayVersionString)
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { service?.clearNotification() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { service?.finishSession() }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        MainActor.assumeIsolated { service?.finishCheck() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == UpdateService.notificationID,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await service?.checkForUpdates()
    }
}
