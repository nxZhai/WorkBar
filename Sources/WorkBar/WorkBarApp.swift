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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var model: WorkBarModel!
    private var sleepObserver: NSObjectProtocol?

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
            button.action = #selector(self.togglePopover)
        }

        self.popover = NSPopover()
        self.popover.behavior = .transient
        self.popover.animates = true
        self.popover.contentSize = NSSize(width: 380, height: 460)
        self.popover.contentViewController = NSHostingController(
            rootView: WorkBarView(
                model: self.model,
                onQuit: { NSApp.terminate(nil) }))
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
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
    }

    @objc private func togglePopover() {
        guard let button = self.statusItem.button else { return }
        if self.popover.isShown {
            self.popover.performClose(nil)
        } else {
            self.popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY)
            self.popover.contentViewController?.view.window?.makeKey()
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
        let clock = if hours > 0 {
            "\(hours):\(String(format: "%02d", minutes))"
        } else {
            "\(minutes):\(String(format: "%02d", seconds))"
        }
        let prefix = remaining < 0 ? "+" : ""
        let title = String(task.title.prefix(12))
        button.title = "\(title) \(prefix)\(clock)"
        button.imagePosition = .imageLeading
        button.setAccessibilityTitle("WorkBar，正在进行：\(task.title)，\(prefix)\(clock)")
    }
}
