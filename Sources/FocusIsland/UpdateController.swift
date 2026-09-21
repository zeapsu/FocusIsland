import Combine
import Foundation
@preconcurrency import Sparkle

/// A small adapter around Sparkle's standard user interface. Scheduled checks
/// only light the status-item indicator; a user action opens Sparkle's normal
/// update flow.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var statusText: String?
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isEnabled = false
    @Published private(set) var automaticallyChecksForUpdates = false

    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    init(disabled: Bool) {
        super.init()

        guard !disabled else {
            statusText = "Updates are unavailable in QA mode."
            return
        }

        // `swift run` and development binaries are not application bundles and
        // intentionally do not carry release feed/signing configuration.
        guard Bundle.main.bundleURL.pathExtension == "app",
              let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feedURL)?.scheme == "https",
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "Updates are configured in release builds."
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        // Update checks need only the signed feed. Do not append hardware,
        // operating-system, locale, or other system-profile fields.
        controller.updater.sendsSystemProfile = false
        do {
            try controller.updater.start()
            self.controller = controller
            isEnabled = true
            automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
            canCheckForUpdates = controller.updater.canCheckForUpdates
            canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor in self?.canCheckForUpdates = updater.canCheckForUpdates }
            }
        } catch {
            statusText = "Updates are unavailable in this build."
        }
    }

    var hasAvailableUpdate: Bool { availableVersion != nil }
    var checkButtonTitle: String {
        if let availableVersion { return "Update to v\(availableVersion)…" }
        return "Check for Updates…"
    }

    /// Sparkle continues to select updates using its own version comparison.
    /// This is display-only, so CI releases sharing a marketing version remain
    /// distinguishable by their monotonically increasing bundle build.
    nonisolated static func versionLabel(_ item: SUAppcastItem) -> String {
        versionLabel(displayVersion: item.displayVersionString, buildVersion: item.versionString)
    }

    nonisolated static func versionLabel(displayVersion: String, buildVersion: String) -> String {
        "\(displayVersion) (\(buildVersion))"
    }

    func checkForUpdates() {
        guard let controller else { return }
        guard controller.updater.canCheckForUpdates else {
            statusText = "An update check is already in progress."
            return
        }
        statusText = "Checking for updates…"
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let controller else { return }
        controller.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
    }

    // MARK: Sparkle gentle scheduled reminders

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Focus Island is an LSUIElement utility. A scheduled update should
        // remain a status-item affordance and never interrupt a focus block.
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        let version = Self.versionLabel(update)
        Task { @MainActor [weak self] in
            self?.availableVersion = version
            self?.statusText = "Version \(version) is available."
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // Attention only means Sparkle's alert became visible or focused. It is
        // not a dismissal, skip, or installation choice, so keep our badge
        // until the updater tells us which choice the user actually made.
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor [weak self] in self?.statusText = nil }
    }

    // MARK: Sparkle updater state

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = Self.versionLabel(item)
        availableVersion = version
        statusText = "Version \(version) is available."
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        recordNoUpdate()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if isNoUpdateError(error) {
            recordNoUpdate()
        } else {
            statusText = "Couldn’t check for updates."
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard let error else { return }
        if isNoUpdateError(error) {
            recordNoUpdate()
        } else if availableVersion == nil {
            statusText = "Couldn’t check for updates."
        }
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        let version = Self.versionLabel(updateItem)
        switch choice {
        case .skip:
            availableVersion = nil
            statusText = "Version \(version) was skipped."
        case .dismiss:
            // Sparkle may remind the user again later, and our status item
            // remains an immediate, non-intrusive way to resume the update.
            availableVersion = version
            statusText = "Version \(version) is available."
        case .install:
            availableVersion = version
            statusText = "Installing version \(version)…"
        @unknown default:
            break
        }
    }

    private func isNoUpdateError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)
    }

    private func recordNoUpdate() {
        availableVersion = nil
        statusText = "No new update is available."
    }
}
