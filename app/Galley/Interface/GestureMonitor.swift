import AppKit
import SwiftUI
#if DEBUG
import WebKit
#endif

/// Trackpad gestures for the whole window, read from raw scroll events:
///
/// - **Horizontal two-finger swipe** — moves along the panel axis, and the
///   column follows the fingers. Fingers right reveal, fingers left hide.
/// - **Pull past the end** — a *fresh* downward scroll that starts when the
///   page is already at its end fills the ring in the footer; releasing it
///   full opens the next document. Momentum and a scroll that merely arrives
///   at the end never count, so skimming cannot flip the page.
@MainActor
final class GestureMonitor {
    private weak var window: NSWindow?
    private let model: AppModel
    private var monitor: Any?

    private var axis: AxisLock.Axis?
    private var fingerX: CGFloat = 0
    private var lock = AxisLock()
    /// Events held back while the direction is still unclear.
    private var held: [NSEvent] = []
    private var pullArmed = false
    private var pull: CGFloat = 0
    private var wheelPull: CGFloat = 0
    /// After a pull opens the next page, its momentum must not scroll it.
    private var swallowMomentum = false
    private var wheelReset: Task<Void, Never>?

    /// Points of finger travel for a full column reveal.
    private let swipeDistance: CGFloat = 200
    /// Points of extra pull to continue to the next document.
    private let pullDistance: CGFloat = 150

    init(window: NSWindow, model: AppModel) {
        self.window = window
        self.model = model
        #if DEBUG
        Self.current = self
        #endif
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window || isInjecting else { return event }

        // Mouse wheels have no phases: count notches past the end instead.
        if event.phase.isEmpty, event.momentumPhase.isEmpty {
            return handleWheel(event)
        }
        // Momentum after a horizontal swipe must not scroll the page sideways,
        // nor momentum from a pull scroll the page it just opened.
        if !event.momentumPhase.isEmpty {
            return axis == .horizontal || swallowMomentum ? nil : event
        }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swallowMomentum = false
        }
        if event.phase.contains(.began) {
            axis = nil
            fingerX = 0
            lock = AxisLock()
            held = []
            pull = 0
            pullArmed = model.settings.pullToContinue && model.isReaderAtBottom && isOverPage(event) && hasNext
        }

        if event.phase.contains(.changed) || event.phase.contains(.began) {
            let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            fingerX += dx
            if axis == nil {
                // Nothing reaches the page until the gesture has picked an
                // axis, so a sideways swipe never nudges the text vertically.
                switch lock.add(x: event.scrollingDeltaX, y: event.scrollingDeltaY) {
                case nil:
                    held.append(event)
                    return nil
                case .horizontal?:
                    axis = .horizontal
                    held = []
                case .vertical?:
                    axis = .vertical
                    if pullArmed { updatePull(towardEnd: -lock.y + event.scrollingDeltaY) }
                    deliverHeld()
                }
            }
            switch axis {
            case .horizontal:
                model.swipeProgress = swipeProgress()
                return nil
            case .vertical, nil:
                if pullArmed { updatePull(towardEnd: -event.scrollingDeltaY) }
                return event
            }
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            let cancelled = event.phase.contains(.cancelled)
            if axis == .horizontal {
                finishSwipe(cancelled: cancelled)
                return nil
            }
            // Too short to pick an axis: it was a small scroll after all.
            deliverHeld()
            if pullArmed {
                let ready = pull >= pullDistance && !cancelled
                pullArmed = false
                pull = 0
                model.reader.setPull(0)
                if ready {
                    swallowMomentum = true
                    model.goToNext()
                }
            }
        }
        return event
    }

    #if DEBUG
    static weak var current: GestureMonitor?
    private var isInjecting = false

    /// Feeds a synthesized scroll event through the real handler as if it
    /// came from this window over the page (`DebugAutomation`'s gestures —
    /// an app cannot attach its own window to an event it builds).
    func inject(_ event: NSEvent) {
        isInjecting = true
        defer { isInjecting = false }
        if let passed = handle(event), passed.phase.contains(.changed) || passed.phase.contains(.began) {
            // The page would have scrolled: do it, so a pull meets a real end.
            model.reader.webView.evaluateJavaScript("window.scrollBy(0, \(-passed.scrollingDeltaY))")
        }
    }
    #else
    private let isInjecting = false
    #endif

    /// Hands held-back events to the page untouched, ahead of the current
    /// one, so a vertical scroll loses no distance to the axis decision.
    private func deliverHeld() {
        let events = held
        held = []
        guard !events.isEmpty else { return }
        #if DEBUG
        if isInjecting {
            let y = events.reduce(0) { $0 + $1.scrollingDeltaY }
            model.reader.webView.evaluateJavaScript("window.scrollBy(0, \(-y))")
            return
        }
        #endif
        // Straight to the window: they have been through this monitor once.
        for event in events { window?.sendEvent(event) }
    }

    // MARK: Swipe

    /// -1…1, with rubber-banding where there is no further level to go to.
    private func swipeProgress() -> Double {
        let raw = Double(fingerX / swipeDistance)
        let level = model.level.rawValue
        if raw > 0, level >= PanelLevel.workspaces.rawValue { return 0 }
        if raw < 0, level <= PanelLevel.page.rawValue { return 0 }
        return min(1, max(-1, raw))
    }

    private func finishSwipe(cancelled: Bool) {
        let progress = model.swipeProgress
        let level = model.level.rawValue
        if !cancelled, progress > 0.32, let next = PanelLevel(rawValue: level + 1) {
            model.setLevel(next)
        } else if !cancelled, progress < -0.32, let previous = PanelLevel(rawValue: level - 1) {
            model.setLevel(previous)
        } else {
            withAnimation(.galleyPanel) { model.swipeProgress = 0 }
        }
        // `axis` stays horizontal until the next gesture, so its momentum is swallowed.
    }

    // MARK: Pull

    private var hasNext: Bool {
        guard let current = model.current, let workspace = model.currentWorkspace else { return false }
        return model.nextFile(after: current.file, in: workspace) != nil
    }

    private func updatePull(towardEnd delta: CGFloat) {
        pull += delta
        if pull < -4 {
            // Scrolled back up: this gesture is reading, not turning the page.
            pullArmed = false
            pull = 0
            model.reader.setPull(0)
            return
        }
        model.reader.setPull(Double(max(0, pull) / pullDistance))
    }

    private func handleWheel(_ event: NSEvent) -> NSEvent? {
        guard model.settings.pullToContinue, isOverPage(event), hasNext, model.isReaderAtBottom else {
            wheelPull = 0
            return event
        }
        let towardEnd = -event.scrollingDeltaY
        guard towardEnd > 0 else {
            wheelPull = 0
            model.reader.setPull(0)
            return event
        }
        wheelPull += towardEnd * (event.hasPreciseScrollingDeltas ? 1 : 10)
        let threshold = pullDistance * 1.6
        model.reader.setPull(Double(wheelPull / threshold))
        if wheelPull >= threshold {
            wheelPull = 0
            model.reader.setPull(0)
            model.goToNext()
        }
        wheelReset?.cancel()
        wheelReset = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            self.wheelPull = 0
            self.model.reader.setPull(0)
        }
        return event
    }

    private func isOverPage(_ event: NSEvent) -> Bool {
        if isInjecting { return true }
        let webView = model.reader.webView
        guard webView.window === window else { return false }
        let point = webView.convert(event.locationInWindow, from: nil)
        return webView.bounds.contains(point)
    }
}

/// Decides whether a two-finger gesture is a sideways swipe or a scroll,
/// from the travel on both axes once there is enough of it to tell.
nonisolated struct AxisLock {
    enum Axis: Equatable { case horizontal, vertical }

    /// Points of travel before deciding: enough to see a direction, little
    /// enough that a scroll does not feel late.
    static let distance: CGFloat = 10
    /// Horizontal wins only when clearly sideways — within about 40° of
    /// the horizontal — so a slightly slanted scroll stays a scroll.
    static let bias: CGFloat = 1.2

    private(set) var x: CGFloat = 0
    private(set) var y: CGFloat = 0

    /// Adds one event's deltas; returns the axis once it is decided.
    mutating func add(x dx: CGFloat, y dy: CGFloat) -> Axis? {
        x += dx
        y += dy
        guard abs(x) + abs(y) >= Self.distance else { return nil }
        return abs(x) > abs(y) * Self.bias ? .horizontal : .vertical
    }
}
