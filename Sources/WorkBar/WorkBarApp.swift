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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        self.popover.contentSize = NSSize(width: 340, height: 220)
        self.popover.contentViewController = NSHostingController(
            rootView: ShellView(onQuit: { NSApp.terminate(nil) }))
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
}

private struct ShellView: View {
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            Text("WorkBar")
                .font(.headline)
            Text("离线工作计时器")
                .foregroundStyle(.secondary)
            Button("退出 WorkBar", action: self.onQuit)
                .keyboardShortcut("q")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
