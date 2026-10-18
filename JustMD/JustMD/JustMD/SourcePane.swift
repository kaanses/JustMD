import SwiftUI
import AppKit

/// Read-only view of the raw Markdown. JustMD is a viewer: edits happen in the user's editor
/// and arrive here through file watching, so nothing typed can be silently lost.
struct SourcePane: NSViewRepresentable {
    let content: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.sourcePaneBg
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        // Only lay out what's visible — a 1 MB source otherwise lays out in full on open
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask([.width])
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = Theme.sourcePaneText
        textView.backgroundColor = Theme.sourcePaneBg
        textView.textContainerInset = NSSize(width: 12, height: 12)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              content != context.coordinator.lastShown else { return }
        context.coordinator.lastShown = content
        textView.string = content
    }

    final class Coordinator {
        // Our own native copy: comparing against textView.string (storage-backed) is slow
        var lastShown: String?
    }
}
