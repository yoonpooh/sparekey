import AppKit
import CoreGraphics
import SparekeyCore

private final class CoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// AppKit state lives only on the helper's main thread. The socket and relock watcher
// schedule changes here; the panels never activate the application.
final class CoverOverlay {
    static let shared = CoverOverlay()
    private var panels: [NSPanel] = []
    private var buttonPanel: NSPanel?
    private var visible = false
    private var ownership = CoverOwnership()
    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            if self?.visible == true { self?.rebuild() }
        }
    }

    static func schedulePendingShow(attempt: UInt64, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            guard shared.ownership.begin(attempt: attempt) else { completion(false); return }
            shared.show()
            completion(!shared.panels.isEmpty)
        }
    }
    static func scheduleBind(attempt: UInt64, token: UInt64) {
        DispatchQueue.main.async {
            switch shared.ownership.bind(attempt: attempt, token: token) {
            case .ended:
                shared.hide()
            case .missing, .bound:
                break
            }
        }
    }
    static func scheduleHide(attempt: UInt64) {
        DispatchQueue.main.async {
            if shared.ownership.cancel(attempt: attempt) { shared.hide() }
        }
    }
    static func scheduleHide(token: UInt64) {
        DispatchQueue.main.async {
            if shared.ownership.end(token: token) { shared.hide() }
        }
    }
    static func scheduleHide() {
        DispatchQueue.main.async {
            shared.ownership.clear()
            shared.hide()
        }
    }

    func show() { visible = true; rebuild() }
    func hide() {
        visible = false
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        buttonPanel?.orderOut(nil)
        buttonPanel?.close()
        buttonPanel = nil
    }

    private func panel(frame: NSRect, screen: NSScreen, level: NSWindow.Level) -> CoverPanel {
        let panel = CoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false, screen: screen)
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        return panel
    }

    private func rebuild() {
        hide()
        visible = true
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let mainID = CGMainDisplayID()
        let main = screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainID
        } ?? screens[0]
        for screen in screens {
            let cover = panel(frame: screen.frame, screen: screen, level: .screenSaver)
            cover.ignoresMouseEvents = true
            cover.isOpaque = true
            cover.backgroundColor = .black
            cover.contentView = screen === main
                ? CoverArtworkView(frame: NSRect(origin: .zero, size: screen.frame.size))
                : NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            cover.orderFrontRegardless()
            panels.append(cover)
        }
        let frame = CoverLayout.buttonFrame(in: main.frame)
        let button = panel(frame: frame, screen: main,
                           level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
        button.ignoresMouseEvents = false
        button.isOpaque = false
        button.backgroundColor = .clear
        let view = CoverLockButtonView(frame: NSRect(origin: .zero, size: frame.size))
        view.action = { [weak self] in
            guard self?.visible == true else { return }
            Transport.lockFromButton()
        }
        button.contentView = view
        button.orderFrontRegardless()
        buttonPanel = button
    }
}
