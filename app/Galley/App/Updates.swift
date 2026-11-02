import Sparkle
import SwiftUI

/// Updates through Sparkle, from the feed on the newest GitHub release
/// (`SUFeedURL` in Info.plist). Sparkle asks the reader before it checks on
/// its own; after that, Settings → General turns the checks on and off.
/// Debug builds never check: they would offer to replace themselves.
@MainActor
@Observable
final class Updates {
    static let shared = Updates()

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// Whether Galley checks once a day; mirrors Sparkle's own setting.
    var checksAutomatically: Bool {
        didSet {
            guard checksAutomatically != controller.updater.automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    static var isAvailable: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: Self.isAvailable, updaterDelegate: nil, userDriverDelegate: nil)
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        // Sparkle's first-run question changes the setting behind our back.
        observation = controller.updater.observe(\.automaticallyChecksForUpdates) { updater, _ in
            let value = updater.automaticallyChecksForUpdates
            Task { @MainActor in
                if Updates.shared.checksAutomatically != value { Updates.shared.checksAutomatically = value }
            }
        }
    }

    /// At launch: creating the controller starts the updater, which checks
    /// on its schedule once the reader has said it may.
    func start() {}

    /// Galley → Check for Updates…: always shows what it found.
    func checkNow() {
        guard Self.isAvailable else { NSSound.beep(); return }
        controller.checkForUpdates(nil)
    }
}
