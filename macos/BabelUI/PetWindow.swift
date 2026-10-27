import AppKit
import SwiftUI

/// A transparent, always-on-top window the crab lives in. It roams the screen by moving the
/// window; drag it to pick the crab up; click it to play (or to open Claude Code on Babel).
final class PetWindow {
    static let defaultsKey = "showPet"
    private static let originKey = "petOrigin"

    let brain = PetBrain()
    private let panel: NSPanel
    private let queue: QueueMonitor
    private let makeMenu: () -> NSMenu
    private var timer: Timer?
    private var lastTick = Date()
    private var wasBusy: Bool?
    private var hostView: NSView?

    /// Float above every window (off by default: the crab is an ordinary window others can cover).
    static var onTop: Bool {
        get { UserDefaults.standard.bool(forKey: "petOnTop") }
        set { UserDefaults.standard.set(newValue, forKey: "petOnTop") }
    }

    func setOnTop(_ on: Bool) {
        Self.onTop = on
        panel.level = on ? .floating : .normal
    }

    static var wanted: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    var isVisible: Bool { panel.isVisible }
    var window: NSWindow { panel }
    private var busy: Bool { (queue.gpu?.gpuCount ?? 0) > 0 }

    init(queue: QueueMonitor, makeMenu: @escaping () -> NSMenu) {
        self.queue = queue
        self.makeMenu = makeMenu
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: PetScene.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = Self.onTop ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.setFrameOrigin(Self.savedOrigin(size: panel.frame.size))
    }

    func show() {
        if hostView == nil {
            let view = PetView(queue: queue, brain: brain, window: panel,
                               click: { [weak self] in self?.clicked() },
                               dropped: { [weak self] in self?.dropped() })
            let host = FirstClickHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: PetScene.size)
            panel.contentView = host
            hostView = host
        }
        panel.orderFrontRegardless()
        if timer == nil {
            lastTick = Date()
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)   // keep walking while a menu is open
            timer = t
        }
    }

    /// Hiding drops the view and the timer, so a hidden crab costs nothing.
    func hide() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        panel.contentView = NSView()
        hostView = nil
    }

    func setWanted(_ on: Bool) {
        Self.wanted = on
        on ? show() : hide()
    }

    /// Run somewhere on this screen right now.
    func goForARun() {
        brain.go(to: PetBrain.randomPoint(in: roamArea()), from: panel.frame.origin, running: true)
    }

    // MARK: - Behaviour

    private func tick() {
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now

        // GPUs just started: dinner is served! GPUs just stopped: back to hungry.
        if let wasBusy, wasBusy != busy, brain.action != .held {
            busy ? brain.perform(.eat(PetBrain.foods.randomElement()!), for: 5.4) : brain.perform(.hungry, for: 6)
        }
        wasBusy = busy

        if brain.action.isMoving, let target = brain.target {
            let o = panel.frame.origin
            let dx = target.x - o.x, dy = target.y - o.y
            let dist = hypot(dx, dy)
            let speed: CGFloat = brain.action == .run ? 170 : 45
            if dist < 3 {
                brain.next(busy: busy, area: roamArea(), origin: o)
            } else {
                let step = min(dist, speed * dt)
                panel.setFrameOrigin(NSPoint(x: o.x + dx / dist * step, y: o.y + dy / dist * step))
            }
        } else if brain.finished {
            brain.next(busy: busy, area: roamArea(), origin: panel.frame.origin)
        }
    }

    /// Where the window's origin may go: anywhere the crab stays on the current screen.
    private func roamArea() -> CGRect {
        let screen = panel.screen ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return .zero }
        let s = PetScene.size
        return CGRect(x: vf.minX - 30, y: vf.minY - 20, width: max(0, vf.width - s.width + 60),
                      height: max(0, vf.height - s.height + 30))
    }

    private func clicked() {
        brain.perform(.love, for: 1.8)
        // Let the hop start, then offer things to do.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let menu = self.makeMenu()
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func dropped() {
        brain.perform(.land, for: 1.5)
        Self.saveOrigin(panel.frame.origin)
    }

    private static func savedOrigin(size: NSSize) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: originKey) {
            let p = NSPointFromString(s)
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -60, dy: -60).contains(p) }) { return p }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - size.width - 12, y: vf.minY - 10)
    }

    static func saveOrigin(_ p: NSPoint) {
        UserDefaults.standard.set(NSStringFromPoint(p), forKey: originKey)
    }
}

/// Clicks reach the crab even while another app is active.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PetView: View {
    let queue: QueueMonitor
    let brain: PetBrain
    weak var window: NSWindow?
    let click: () -> Void
    let dropped: () -> Void

    @State private var drag: (mouse: NSPoint, origin: NSPoint, moved: Bool)?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            PetScene(gpu: queue.gpu, action: brain.action, started: brain.started, facing: brain.facing, now: context.date)
        }
        .frame(width: PetScene.size.width, height: PetScene.size.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard let window else { return }
                    let mouse = NSEvent.mouseLocation
                    if drag == nil { drag = (mouse, window.frame.origin, false) }
                    guard var d = drag else { return }
                    if !d.moved && hypot(mouse.x - d.mouse.x, mouse.y - d.mouse.y) > 3 {
                        d.moved = true
                        drag = d
                        brain.perform(.held, for: .infinity)
                    }
                    if d.moved {
                        window.setFrameOrigin(NSPoint(x: d.origin.x + mouse.x - d.mouse.x, y: d.origin.y + mouse.y - d.mouse.y))
                    }
                }
                .onEnded { _ in
                    let moved = drag?.moved ?? false
                    drag = nil
                    moved ? dropped() : click()
                }
        )
        .help("Click me! · drag to pick me up")
    }
}
