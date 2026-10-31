// Sends commands to a running debug build of Galley (see DebugAutomation).
// Usage: swift tools/galley-debug.swift level.3 theme.sepia snapshot
import Foundation

for command in CommandLine.arguments.dropFirst() {
    if command.hasPrefix("wait.") {
        Thread.sleep(forTimeInterval: (Double(command.dropFirst(5)) ?? 500) / 1000)
        continue
    }
    DistributedNotificationCenter.default().postNotificationName(
        .init("com.aliemir.galley.debug." + command), object: nil, userInfo: nil, deliverImmediately: true
    )
    Thread.sleep(forTimeInterval: 0.25)
}
