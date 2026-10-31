import CoreServices
import Foundation

/// Watches a folder tree with FSEvents and reports, after a short quiet
/// period, the paths that changed. Agents often write a file in several
/// bursts; the latency folds them into one report.
@MainActor
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init?(url: URL, latency: TimeInterval = 0.3, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            let changed = Array(array.prefix(count))
            MainActor.assumeIsolated { watcher.onChange(changed) }
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    isolated deinit {
        stop()
    }
}
