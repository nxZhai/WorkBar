import AppKit
import SwiftUI

@main
struct WorkBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private final class WorkBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: WorkBarPanel!
    private var model: WorkBarModel!
    private var sleepObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        self.model = WorkBarModel()
        self.model.onChange = { [weak self] in
            self?.updateStatusItem()
        }

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = self.statusItem.button {
            button.image = NSImage(
                systemSymbolName: "hourglass",
                accessibilityDescription: "WorkBar")
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("打开 WorkBar")
            button.target = self
            button.action = #selector(self.togglePanel)
        }

        self.panel = WorkBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 590),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        self.panel.title = "WorkBar"
        self.panel.isFloatingPanel = true
        self.panel.level = .statusBar
        self.panel.backgroundColor = .clear
        self.panel.isOpaque = false
        self.panel.hasShadow = true
        self.panel.titleVisibility = .hidden
        self.panel.titlebarAppearsTransparent = true
        self.panel.hidesOnDeactivate = false
        self.panel.isReleasedWhenClosed = false
        self.panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel.contentViewController = NSHostingController(
            rootView: WorkBarView(
                model: self.model,
                onQuit: { NSApp.terminate(nil) }))
        self.panel.contentView?.wantsLayer = true
        self.panel.contentView?.layer?.cornerRadius = 18
        self.panel.contentView?.layer?.cornerCurve = .continuous
        self.panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        self.panel.contentView?.layer?.masksToBounds = true
        self.updateStatusItem()

        self.sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.model.pauseForSystemEvent()
                }
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.model.shutdown()
        self.closePanel()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
    }

    @objc private func togglePanel() {
        guard let button = self.statusItem.button else { return }
        if self.panel.isVisible {
            self.closePanel()
        } else {
            self.showPanel(anchor: button)
        }
    }

    private func showPanel(anchor button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = self.panel.frame.size
        let visibleFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(
            max(buttonFrame.midX - panelSize.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - panelSize.width - 8)
        let y = max(visibleFrame.minY + 8, buttonFrame.minY - panelSize.height - 8)

        self.panel.setFrameOrigin(NSPoint(x: x, y: y))
        self.panel.orderFrontRegardless()
        self.panel.makeKey()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        self.outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.closePanel()
            }
    }

    private func closePanel() {
        self.panel?.orderOut(nil)
        self.panel?.resignKey()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func updateStatusItem() {
        guard let button = self.statusItem?.button else { return }
        guard let taskID = self.model?.engine.activeTaskID,
              let task = self.model?.tasks.first(where: { $0.id == taskID })
        else {
            button.title = ""
            button.imagePosition = .imageOnly
            button.setAccessibilityTitle("WorkBar，当前没有活动任务")
            return
        }
        let remaining = self.model.remaining(for: taskID)
        let total = abs(Int(remaining.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        let prefix = remaining < 0 ? "+" : ""
        let title = String(task.title.prefix(12))
        button.title = "\(title) \(prefix)\(clock)"
        button.imagePosition = .imageLeading
        button.setAccessibilityTitle("WorkBar，正在进行：\(task.title)，\(prefix)\(clock)")
    }
}
