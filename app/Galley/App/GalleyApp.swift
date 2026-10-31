import SwiftUI

@main
struct GalleyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Galley", id: "main") {
            MainView()
                .environment(model)
                .onAppear {
                    appDelegate.model = model
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
    var model: AppModel?
    #if DEBUG
    var automation: DebugAutomation?
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareToQuit()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model?.saveState()
    }
}
