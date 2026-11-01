// Records one window — only that window, whatever is in front of it — as
// PNG frames, for the guide's GIFs (tools/capture-guide.sh turns them into
// a GIF with ffmpeg). A screen-region recording would also catch any window
// that happens to overlap.
// Usage: swift tools/record-window.swift <window id> <seconds> <fps> <out folder>
import AppKit
import CoreMedia
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count == 5, let windowID = CGWindowID(arguments[1]),
      let seconds = Double(arguments[2]), let fps = Int32(arguments[3]) else {
    print("usage: record-window.swift <window id> <seconds> <fps> <out folder>")
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[4], isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

/// Keeps the latest picture of the window; `tick` writes it out at a steady
/// rate, so still moments last as long in the GIF as they did on screen
/// (the stream sends nothing while the window does not change).
final class Recorder: NSObject, SCStreamOutput {
    var frame = 0
    var latest: CGImage?
    let folder: URL
    let context = CIContext()
    init(folder: URL) { self.folder = folder }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        // Half size: the GIF is smaller still, and a frame must be written
        // faster than the next one is due.
        let image = CIImage(cvPixelBuffer: pixels).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        latest = context.createCGImage(image, from: image.extent)
    }

    func tick() {
        guard let latest else { return }
        frame += 1
        let url = folder.appendingPathComponent(String(format: "frame%05d.png", frame))
        try? NSBitmapImageRep(cgImage: latest).representation(using: .png, properties: [:])?.write(to: url)
    }
}

let recorder = Recorder(folder: folder)
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
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: fps)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        // On a clock, so a slow write delays one frame, not every one after.
        let start = Date()
        var next = start
        while Date().timeIntervalSince(start) < seconds {
            recorder.tick()
            next = next.addingTimeInterval(1 / Double(fps))
            let wait = next.timeIntervalSinceNow
            if wait > 0 { try await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
        }
        try await stream.stopCapture()
        // The rate the frames were really written at, for the GIF's timing.
        let rate = Double(recorder.frame) / Date().timeIntervalSince(start)
        try? String(format: "%.2f", rate).write(to: folder.appendingPathComponent("rate"), atomically: true, encoding: .utf8)
        print("\(recorder.frame) frames in \(folder.path) at \(String(format: "%.1f", rate)) fps")
        exit(0)
    } catch {
        print("recording failed: \(error)")
        exit(1)
    }
}
RunLoop.main.run()
