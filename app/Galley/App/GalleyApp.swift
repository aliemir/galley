import SwiftUI

/// One binary, two ways in: Galley, or the `galley` command (see `CLI`),
/// which does its work and exits before any window exists.
@main
enum Entry {
    static func main() {
        if let arguments = CLI.arguments(CommandLine.arguments) {
            exit(CLI.run(arguments))
        }
        GalleyApp.main()
    }
}

struct GalleyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Galley", id: "main") {
            MainView()
                .environment(model)
                .onAppear {
                    appDelegate.model = model
                    model.listenForFeedbackRequests()
                    model.lookForWatchers()
                    #if DEBUG
                    appDelegate.automation = DebugAutomation(model: model)
                    #endif
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 780)
        .commands { GalleyCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel? {
        didSet {
            guard let model, !pendingURLs.isEmpty else { return }
            model.open(pendingURLs)
            pendingURLs = []
        }
    }
    /// Files opened before the window (and the model with it) was ready —
    /// a double-click in Finder that also launches the app.
    private var pendingURLs: [URL] = []
    #if DEBUG
    var automation: DebugAutomation?
    #endif

    /// Finder's Open With, a double-click, a drop on the Dock icon, `open -a`.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { model.open(urls) } else { pendingURLs += urls }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIcon.apply(ReaderSettings.shared.appIcon)
        Updates.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareToQuit()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model?.saveState()
    }
}
