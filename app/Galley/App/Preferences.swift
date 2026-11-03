import Foundation

/// Where the app keeps its settings. A debug copy on a throwaway library
/// (`-GalleyLibrary`) keeps them apart as well, starting empty each launch,
/// so a test that picks a theme or a sort never changes the reader's.
nonisolated enum Preferences {
    static let store: UserDefaults = {
        #if DEBUG
        if LibraryLocation.isThrowaway, let test = UserDefaults(suiteName: testSuite) {
            test.removePersistentDomain(forName: testSuite)
            return test
        }
        #endif
        // A Debug build's own: its identifier, com.aliemir.galley.debug, is
        // its domain, apart from the installed app's.
        return .standard
    }()

    #if DEBUG
    static let testSuite = "com.aliemir.galley.test"
    #endif
}
