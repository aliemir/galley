// Records one window — only that window, whatever is in front of it — to a
// movie at full Retina resolution, for the guide's GIFs and the website's
// videos (tools/capture-guide.sh converts it with ffmpeg). A screen-region
// recording would also catch any window that happens to overlap.
// Usage: swift tools/record-window.swift <window id> <seconds> <out.mov>
import AppKit
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let windowID = CGWindowID(arguments[1]), let seconds = Double(arguments[2]) else {
    print("usage: record-window.swift <window id> <seconds> <out.mov>")
    exit(2)
}
// ScreenCaptureKit needs the window-server connection AppKit sets up.
_ = NSApplication.shared
let movie = URL(fileURLWithPath: arguments[3])
try? FileManager.default.removeItem(at: movie)

/// Says when the movie file is complete.
final class Finish: NSObject, SCRecordingOutputDelegate {
    var done: CheckedContinuation<Void, Never>?
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        done?.resume()
        done = nil
    }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        print("recording failed: \(error)")
        exit(1)
    }
}

let finish = Finish()
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            print("no window \(windowID)")
            exit(1)
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let output = SCRecordingOutputConfiguration()
        output.outputURL = movie
        output.outputFileType = .mov
        output.videoCodecType = .h264
        let recording = SCRecordingOutput(configuration: output, delegate: finish)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(seconds))
        await withCheckedContinuation { continuation in
            finish.done = continuation
            Task { try? await stream.stopCapture() }
        }
        print("recorded \(movie.path)")
        exit(0)
    } catch {
        print("recording failed: \(error)")
        exit(1)
    }
}
RunLoop.main.run()
