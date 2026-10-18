import SwiftUI
import UniformTypeIdentifiers

/// Menu bar commands. Everything acts on the shared app state, so file watching and
/// bookmarks see files opened from the menu exactly like files opened from Finder.
struct AppCommands: Commands {
    @ObservedObject var tabState: TabState
    let fileCoordinator: FileCoordinator
    let bookmarkStore: BookmarkStore
    @AppStorage(Zoom.storageKey) private var zoom = 1.0
    @AppStorage("showSource") private var showSource = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { openFilePicker() }
                .keyboardShortcut("o", modifiers: .command)
            Menu("Open Recent") {
                // Re-evaluated whenever tabs change, which is when this list changes
                ForEach(bookmarkStore.recentFiles, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        if let resolved = bookmarkStore.resolve(url) { fileCoordinator.open(url: resolved) }
                    }
                }
                Divider()
                Button("Clear Menu") { bookmarkStore.removeAll() }
                    .disabled(bookmarkStore.recentFiles.isEmpty)
            }
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { NotificationCenter.default.post(name: .printPreview, object: nil) }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(tabState.selectedTab == nil)
        }

        CommandGroup(before: .toolbar) {
            Button("Actual Size") { zoom = 1 }
                .keyboardShortcut("0", modifiers: .command)
            Button("Zoom In") { zoom = Zoom.larger(than: zoom) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { zoom = Zoom.smaller(than: zoom) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Button(showSource ? "Hide Source" : "Show Source") { showSource.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
        }

        // Replaces the window's Close: ⌘W closes the current tab, and the window once none are left
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                if tabState.tabs.isEmpty { NSApp.keyWindow?.performClose(nil) } else { tabState.closeSelected() }
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(before: .windowList) {
            Button("Show Previous Tab") { tabState.selectPrevious() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Show Next Tab") { tabState.selectNext() }
                .keyboardShortcut(.tab, modifiers: .control)
            Menu("Select Tab") {
                ForEach(1..<9) { n in
                    Button("Tab \(n)") { tabState.select(index: n - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
                Button("Last Tab") { tabState.selectLast() }
                    .keyboardShortcut("9", modifiers: .command)
            }
            .disabled(tabState.tabs.count < 2)
            Divider()
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(importedAs: "net.daringfireball.markdown"),
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            panel.urls.forEach(fileCoordinator.open)
        }
    }
}
