import AppKit
import SwiftUI

/// Opens ordinary windows (Welcome, Settings) from a menu-bar-only app, reusing a window
/// if it is already open and bringing it to the front.
@MainActor
enum WindowPresenter {
    private static var windows: [String: NSWindow] = [:]

    static func show<Content: View>(id: String, title: String, size: CGSize, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        windows[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close(id: String) {
        windows[id]?.close()
    }
}
