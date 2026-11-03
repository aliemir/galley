import AppKit
import SwiftUI
#if DEBUG
import WebKit
#endif

/// Trackpad gestures for the whole window, read from raw scroll events:
///
/// - **Horizontal two-finger swipe** — moves along the panel axis, and the
///   column follows the fingers. Fingers right reveal, fingers left hide.
/// - **Pull past an edge** — a *fresh* scroll that starts when the page is
///   already at its end (or top) and keeps going fills a ring; releasing it
///   full opens the next (or previous) document. Momentum and a scroll that
///   merely arrives at an edge never count, so skimming cannot flip the page.
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
    private enum PullEdge { case end, start }
    /// Edges this gesture may pull past, set when it begins at one.
    private var pullEdges: Set<PullEdge> = []
    /// The edge being pulled, once the gesture has moved toward one.
    private var pullEdge: PullEdge?
    private var pullArmed: Bool { !pullEdges.isEmpty }
    private var pull: CGFloat = 0
    private var wasReady = false
    private var wheelPull: CGFloat = 0
    private var wheelEdge: PullEdge?
    /// After a pull opens the next page, its momentum must not scroll it.
    private var swallowMomentum = false
    private var wheelReset: Task<Void, Never>?

    /// Points of finger travel for a full column reveal.
    private let swipeDistance: CGFloat = 200
    /// Points of extra pull to continue to the next or previous document.
    private let pullDistance: CGFloat = 220
    /// Mouse-wheel notches count 10 points each; kept apart from the
    /// trackpad's distance so tuning one does not change the other.
    private let wheelPullDistance: CGFloat = 240

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
            pullEdges = []
            pullEdge = nil
            if model.settings.pullToContinue, isOverPage(event) {
                if model.isReaderAtBottom, hasNext { pullEdges.insert(.end) }
                if model.isReaderAtTop, hasPrevious { pullEdges.insert(.start) }
            }
            if pullArmed { model.reader.armPull(true) }
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
                    // A swipe, not a pull: the page gets its bounce back.
                    clearPullState()
                    model.beginPanelMotion()
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
                if pullArmed {
                    updatePull(towardEnd: -event.scrollingDeltaY)
                    // Past the edge the page draws the stretch itself; WebKit
                    // gets the scroll back once the reader turns into the text.
                    if pullEdge != nil { return nil }
                }
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
                let edge = pullEdge
                if ready, let edge {
                    // The stretched page leaves as it is; the next one replaces it.
                    clearPullState()
                    swallowMomentum = true
                    if edge == .end { model.goToNext() } else { model.goToPrevious(landingAtEnd: true) }
                } else {
                    // Its momentum would only bounce the page a second time.
                    if edge != nil { swallowMomentum = true }
                    resetPull()
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
        let raw = AxisLock.swipeProgress(fingerX: fingerX, distance: swipeDistance)
        if raw > 0, model.nextToReveal == nil { return 0 }
        if raw < 0, model.nextToHide == nil { return 0 }
        return min(1, max(-1, raw))
    }

    private func finishSwipe(cancelled: Bool) {
        let progress = model.swipeProgress
        if !cancelled, progress > 0.32, let column = model.nextToReveal {
            model.setColumn(column, visible: true)
        } else if !cancelled, progress < -0.32, let column = model.nextToHide {
            model.setColumn(column, visible: false)
        } else {
            let model = model
            model.beginPanelMotion()
            withAnimation(.galleyPanel, completionCriteria: .logicallyComplete) { model.swipeProgress = 0 } completion: {
                model.endPanelMotion()
            }
        }
        // The swipe's own motion; the settling animation above holds its own.
        model.endPanelMotion()
        // `axis` stays horizontal until the next gesture, so its momentum is swallowed.
    }

    // MARK: Pull

    private var hasNext: Bool {
        guard let current = model.current, let workspace = model.currentWorkspace else { return false }
        return model.nextFile(after: current.file, in: workspace) != nil
    }

    private var hasPrevious: Bool {
        guard let current = model.current, let workspace = model.currentWorkspace else { return false }
        return model.previousFile(before: current.file, in: workspace) != nil
    }

    /// `delta` is scroll toward the end of the page (negative: toward the top).
    private func updatePull(towardEnd delta: CGFloat) {
        if pullEdge == nil, delta != 0 {
            // A short page can be at both edges: the first movement picks one.
            pullEdge = delta > 0 ? (pullEdges.contains(.end) ? .end : nil) : (pullEdges.contains(.start) ? .start : nil)
            if pullEdge == nil { resetPull(); return }
        }
        guard let edge = pullEdge else { return }
        pull += edge == .end ? delta : -delta
        if pull < -4 {
            // Turned back: this gesture is reading, not turning the page.
            resetPull()
            return
        }
        model.reader.setPull(Double(max(0, pull)), threshold: Double(pullDistance), atStart: edge == .start)
        let isReady = pull >= pullDistance
        if isReady, !wasReady {
            // Felt, not just seen: letting go now turns the page.
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        wasReady = isReady
    }

    /// Ends a pull that did not turn the page: the page springs back.
    private func resetPull() {
        if let pullEdge { model.reader.setPull(0, threshold: Double(pullDistance), atStart: pullEdge == .start) }
        clearPullState()
    }

    private func clearPullState() {
        wasReady = false
        if pullArmed { model.reader.armPull(false) }
        pullEdges = []
        pullEdge = nil
        pull = 0
    }

    /// Mouse wheels: notches past the end (or top) count toward the pull.
    private func handleWheel(_ event: NSEvent) -> NSEvent? {
        let towardEnd = -event.scrollingDeltaY
        let edge: PullEdge? = towardEnd > 0
            ? (model.isReaderAtBottom && hasNext ? .end : nil)
            : (towardEnd < 0 && model.isReaderAtTop && hasPrevious ? .start : nil)
        guard model.settings.pullToContinue, isOverPage(event), let edge else {
            clearWheelPull()
            return event
        }
        if wheelEdge != edge { clearWheelPull() }
        wheelEdge = edge
        wheelPull += abs(towardEnd) * (event.hasPreciseScrollingDeltas ? 1 : 10)
        let threshold = wheelPullDistance
        model.reader.setPull(Double(wheelPull), threshold: Double(threshold), atStart: edge == .start)
        if wheelPull >= threshold {
            wheelEdge = nil
            wheelPull = 0
            if edge == .end { model.goToNext() } else { model.goToPrevious(landingAtEnd: true) }
        }
        wheelReset?.cancel()
        wheelReset = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.clearWheelPull()
        }
        return event
    }

    private func clearWheelPull() {
        if let wheelEdge { model.reader.setPull(0, threshold: 1, atStart: wheelEdge == .start) }
        wheelEdge = nil
        wheelPull = 0
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

    /// Finger travel that moves no column: small and accidental swipes leave
    /// the panels, and the text beside them, alone.
    static let swipeDeadZone: CGFloat = 40

    /// -1…1 of a column's reveal for `fingerX` points of sideways travel,
    /// counted from the end of the dead zone.
    static func swipeProgress(fingerX: CGFloat, distance: CGFloat) -> Double {
        let past = max(0, abs(fingerX) - swipeDeadZone)
        return Double((fingerX < 0 ? -past : past) / distance)
    }

    /// Adds one event's deltas; returns the axis once it is decided.
    mutating func add(x dx: CGFloat, y dy: CGFloat) -> Axis? {
        x += dx
        y += dy
        guard abs(x) + abs(y) >= Self.distance else { return nil }
        return abs(x) > abs(y) * Self.bias ? .horizontal : .vertical
    }
}
