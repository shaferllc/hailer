import AppKit
import SwiftUI

/// Owns the floating prompter window, its keyboard/scroll event monitors,
/// and the flip between full prompter and one-line ticker.
@MainActor
final class PrompterController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isTicker = false

    let engine: PrompterEngine
    private let settings: PrompterSettings
    private(set) var scriptID: UUID?
    private weak var store: ScriptStore?

    private var window: NSWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var savedFrame: NSRect?     // prompter frame remembered across ticker flips
    private var lastFullFrame: NSRect?  // remembered across open/close in one run

    init(settings: PrompterSettings) {
        self.settings = settings
        self.engine = PrompterEngine(settings: settings)
        super.init()
    }

    var isPresenting: Bool { window != nil }

    // MARK: Present / close

    func present(scriptID: UUID, store: ScriptStore) {
        self.store = store

        if let window, self.scriptID == scriptID {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        persistPosition() // switching scripts while open: save the old spot
        self.scriptID = scriptID

        let fraction = store.script(scriptID)?.savedProgress ?? 0
        engine.reset(fraction: fraction >= 0.999 ? 0 : fraction)
        engine.onPersist = { [weak self] fraction in
            self?.persistPosition(fraction)
        }

        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }

        let root = PrompterRootView(
            controller: self,
            engine: engine,
            settings: settings,
            store: store,
            scriptID: scriptID
        )
        window.title = store.script(scriptID)?.title ?? "Prompter"
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        engine.start()
        installMonitors()
    }

    func closeWindow() {
        window?.close()
    }

    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    func persistPosition(_ fraction: Double? = nil) {
        guard let scriptID, let store, window != nil else { return }
        store.updateProgress(scriptID, fraction: fraction ?? engine.progressFraction)
    }

    // MARK: Ticker flip

    func toggleTicker() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        engine.pendingFraction = engine.progressFraction // keep place across relayout
        isTicker.toggle()

        if isTicker {
            savedFrame = window.frame
            let vis = window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let width = min(vis.width - 40, vis.width * 0.82)
            let height: CGFloat = 92
            let frame = NSRect(
                x: vis.midX - width / 2,
                y: vis.maxY - height - 8,
                width: width, height: height
            )
            window.setFrame(frame, display: true, animate: true)
            setStandardButtonsHidden(true)
        } else {
            setStandardButtonsHidden(false)
            if let savedFrame {
                window.setFrame(savedFrame, display: true, animate: true)
            }
            savedFrame = nil
        }
    }

    private func setStandardButtonsHidden(_ hidden: Bool) {
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let frame = lastFullFrame ?? NSRect(x: 0, y: 0, width: 900, height: 620)
        let w = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        if lastFullFrame == nil {
            w.center()
        }
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = .black
        w.level = .floating
        w.collectionBehavior = [.fullScreenPrimary, .managed]
        w.minSize = NSSize(width: 420, height: 64)
        w.isReleasedWhenClosed = false
        w.delegate = self
        return w
    }

    // MARK: Event monitors

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleScroll(event) ?? false }
            return handled ? nil : event
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        keyMonitor = nil
        scrollMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }

        switch event.keyCode {
        case 49: // space
            engine.togglePlay()
            return true
        case 53: // escape
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            } else {
                window.close()
            }
            return true
        case 123, 125: // left, down
            engine.nudgeSpeed(-10)
            return true
        case 124, 126: // right, up
            engine.nudgeSpeed(10)
            return true
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r":
            engine.restart()
            return true
        case "t":
            toggleTicker()
            return true
        case "m":
            settings.mirrored.toggle()
            return true
        case "f":
            window.toggleFullScreen(nil)
            return true
        default:
            return false
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let dy = event.scrollingDeltaY
        let dx = event.scrollingDeltaX
        var delta = isTicker ? (abs(dx) >= abs(dy) ? dx : dy) : dy
        if !event.hasPreciseScrollingDeltas {
            delta *= 8 // clicky mouse wheels report line deltas
        }
        engine.scrub(by: -delta)
        return true
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        persistPosition()
        engine.stop()
        removeMonitors()
        lastFullFrame = isTicker ? savedFrame : window?.frame
        isTicker = false
        savedFrame = nil
        window?.delegate = nil
        window?.contentView = nil // break the controller <-> hosting-view cycle
        window = nil
        scriptID = nil
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.level = .normal // floating windows can't own a fullscreen space
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window?.level = .floating
    }
}
