import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var tabState: TabState?
    var bookmarkStore: BookmarkStore?
    var fileCoordinator: FileCoordinator?
    private var windowObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The zoom-in open animation reflowed the already-rendered document for ~250 ms.
        // SwiftUI shows the window before applicationDidFinishLaunching, so switch it off on
        // the window's first update, while it is still hidden, then stop listening.
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow, window.styleMask.contains(.titled) else { return }
                window.animationBehavior = .none
                if let observer = self.windowObserver { NotificationCenter.default.removeObserver(observer) }
                self.windowObserver = nil
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        fileCoordinator?.restoreBookmarks()
        applyWindowTheme()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyWindowTheme()
    }

    private static let windowBg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)  // #0a0a0a
            : NSColor(red: 0.961, green: 0.937, blue: 0.878, alpha: 1)  // #f5efe0
    }

    private func applyWindowTheme() {
        for window in NSApp.windows {
            window.backgroundColor = AppDelegate.windowBg
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            fileCoordinator?.open(url: url)
        }
    }
}
