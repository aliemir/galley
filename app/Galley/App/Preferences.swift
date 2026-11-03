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
        return reader
    }()

    /// The reader's own settings. A Debug build has its own bundle identifier
    /// (`com.aliemir.galley.debug`, for a Dock tile of its own) and so its own
    /// standard domain; it reads and writes the reader's settings here instead,
    /// as it did when the two shared an identifier.
    static let reader: UserDefaults = {
        #if DEBUG
        return UserDefaults(suiteName: "com.aliemir.galley") ?? .standard
        #else
        return .standard
        #endif
    }()

    #if DEBUG
    static let testSuite = "com.aliemir.galley.test"
    #endif
}
