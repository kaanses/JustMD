import SwiftUI
import AppKit

// MARK: - Design tokens

enum Theme {

    // MARK: Adaptive colors (light/dark)
    // nonisolated(unsafe): NSColor refs are safe to hold from any context;
    // AppKit only requires main-thread access when actually rendering.

    nonisolated(unsafe) static let bgPage = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)   // #0a0a0a
            : NSColor(red: 0.961, green: 0.937, blue: 0.878, alpha: 1)   // #f5efe0
    }
    nonisolated(unsafe) static let accentPrimary = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 1)   // #00ff88
            : NSColor(red: 0.722, green: 0.314, blue: 0.000, alpha: 1)   // #b85000
    }
    nonisolated(unsafe) static let accentSecondary = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.000, green: 0.000, blue: 0.431, alpha: 1)   // #ff006e
            : NSColor(red: 0.784, green: 0.000, blue: 0.102, alpha: 1)   // #c8001a
    }
    nonisolated(unsafe) static let textBody = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.533, alpha: 1)                            // #888888
            : NSColor(red: 0.227, green: 0.173, blue: 0.000, alpha: 1)  // #3a2c00
    }
    nonisolated(unsafe) static let textHeading = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.831, alpha: 1)                            // #d4d4d4
            : NSColor(red: 0.110, green: 0.078, blue: 0.000, alpha: 1)  // #1c1400
    }
    nonisolated(unsafe) static let textMuted = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.267, green: 0.267, blue: 0.333, alpha: 1)  // #444455
            : NSColor(red: 0.627, green: 0.533, blue: 0.314, alpha: 1)  // #a08850
    }
    nonisolated(unsafe) static let textH2 = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 1)  // #00ff88
            : NSColor(red: 0.478, green: 0.220, blue: 0.000, alpha: 1)  // #7a3800
    }
    nonisolated(unsafe) static let textH3 = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1.000, green: 0.000, blue: 0.431, alpha: 1)  // #ff006e
            : NSColor(red: 0.784, green: 0.000, blue: 0.102, alpha: 1)  // #c8001a
    }
    nonisolated(unsafe) static let inlineCodeFg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 1)  // #00ff88
            : NSColor(red: 0.627, green: 0.000, blue: 0.082, alpha: 1)  // #a00015
    }
    nonisolated(unsafe) static let inlineCodeBg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 0.07)
            : NSColor(red: 0.784, green: 0.000, blue: 0.102, alpha: 0.08)
    }
    nonisolated(unsafe) static let blockquoteBg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 0.04)
            : NSColor(red: 0.722, green: 0.314, blue: 0.000, alpha: 0.06)
    }
    nonisolated(unsafe) static let tableHeaderBg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1)  // #0d0d0d
            : NSColor(red: 0.910, green: 0.863, blue: 0.753, alpha: 1)  // #e8dcc0
    }
    nonisolated(unsafe) static let tableHeaderFg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 1)  // #00ff88
            : NSColor(red: 0.353, green: 0.220, blue: 0.000, alpha: 1)  // #5a3800
    }
    nonisolated(unsafe) static let tableBg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)  // #0a0a0a
            : NSColor(red: 0.961, green: 0.937, blue: 0.878, alpha: 1)  // #f5efe0
    }
    nonisolated(unsafe) static let tableAltBg = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1)  // #0d0d0d
            : NSColor(red: 0.937, green: 0.910, blue: 0.831, alpha: 1)  // #efe8d4
    }
    nonisolated(unsafe) static let sourcePaneBg = bgPage  // source pane matches page background
    nonisolated(unsafe) static let sourcePaneText = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.831, alpha: 1)                           // #d4d4d4
            : NSColor(red: 0.227, green: 0.173, blue: 0.000, alpha: 1) // #3a2c00
    }

    // MARK: Always-dark (code blocks never adapt)

    nonisolated(unsafe) static let bgCodeBlock  = NSColor(red: 0.020, green: 0.020, blue: 0.020, alpha: 1) // #050505
    nonisolated(unsafe) static let bgCodeHeader = NSColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1) // #0d0d0d
    nonisolated(unsafe) static let codeText     = NSColor(red: 0.784, green: 0.749, blue: 0.690, alpha: 1) // #c8bfb0
    nonisolated(unsafe) static let codeLabel    = NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 0.7) // #00ff88 @70%

    // MARK: Traffic lights (fixed)

    nonisolated(unsafe) static let trafficRed   = NSColor(red: 1.000, green: 0.373, blue: 0.341, alpha: 1) // #ff5f57
    nonisolated(unsafe) static let trafficAmber = NSColor(red: 0.996, green: 0.737, blue: 0.180, alpha: 1) // #febc2e
    nonisolated(unsafe) static let trafficGreen = NSColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1) // #28c840

    // MARK: Helpers
    // nonisolated + MainActor.assumeIsolated: safe because all callers are AppKit drawing
    // callbacks which always execute on the main thread.

    /// The appearance being drawn into — the window, or a light print view — not the app's setting
    static nonisolated func isDark() -> Bool {
        MainActor.assumeIsolated { NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    }

    static nonisolated func h1GradientColors() -> [NSColor] {
        isDark()
            ? [NSColor(white: 0.961, alpha: 1),
               NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 1),
               NSColor(red: 1.000, green: 0.000, blue: 0.431, alpha: 1)]
            : [NSColor(red: 0.110, green: 0.078, blue: 0.000, alpha: 1),
               NSColor(red: 0.722, green: 0.314, blue: 0.000, alpha: 1),
               NSColor(red: 0.784, green: 0.000, blue: 0.102, alpha: 1)]
    }

    static nonisolated func h1RuleColors() -> [NSColor] {
        isDark()
            ? [NSColor(red: 0.000, green: 1.000, blue: 0.533, alpha: 1),
               NSColor(red: 1.000, green: 0.000, blue: 0.431, alpha: 1),
               NSColor.clear]
            : [NSColor(red: 0.722, green: 0.314, blue: 0.000, alpha: 1),
               NSColor(red: 0.784, green: 0.000, blue: 0.102, alpha: 1),
               NSColor.clear]
    }
}

extension Notification.Name {
    /// Sent by File ▸ Print; the visible preview prints itself
    static let printPreview = Notification.Name("JustMDPrintPreview")
}

struct PreviewPane: NSViewRepresentable {
    let content: String
    /// Relative links and images resolve against this
    let folder: URL?
    let zoom: Double
    /// Each document keeps its own scroll position when switching tabs
    let documentID: UUID

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Standard AppKit scroll stack with RichLayoutManager
    // A real NSScrollView (not SwiftUI's ScrollView + sizeThatFits) lets TextKit lay out only
    // what's visible; reporting a height to SwiftUI forced full-document layout on every probe.

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.bgPage
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Zoom.steps.first!
        scrollView.maxMagnification = Zoom.steps.last!

        let textStorage = NSTextStorage()
        let layoutManager = RichLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.backgroundColor = Theme.bgPage
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 48, height: 36)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.layoutManager = layoutManager
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.request(content, folder: folder, documentID: documentID)
        // Magnifying the scroll view scales text and decorations alike, and the text reflows to the narrower width
        if abs(scrollView.magnification - zoom) > 0.001 { scrollView.magnification = zoom }
    }

    // MARK: - Coordinator: renders off the main thread, coalescing bursts of edits

    @MainActor
    final class Coordinator {
        var textView: NSTextView?
        var layoutManager: RichLayoutManager?
        private var lastRequested: String?
        private var folder: URL?
        private var pending: String?
        private var isRendering = false
        private var applied: RenderedDocument?
        private var imageObserver: NSObjectProtocol?
        private var documentID: UUID?
        private var scrollPositions: [UUID: CGPoint] = [:]
        /// Set on tab switch: where the incoming document should open (its last position, or the top)
        private var pendingScroll: CGPoint?
        private var printObserver: NSObjectProtocol?

        init() {
            printObserver = NotificationCenter.default.addObserver(forName: .printPreview, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.printDocument() }
            }
            // An image finished loading: only the attachments showing it need new layout
            imageObserver = NotificationCenter.default.addObserver(forName: ImageStore.didChange, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.refreshImages(note.object as? URL) }
            }
        }

        /// Prints the rendered page in the light theme: a dark page on paper is mostly ink.
        /// A second layout manager on the same text storage lays it out at paper width.
        private func printDocument() {
            guard let textView, let window = textView.window, let storage = textView.textStorage, let source = layoutManager else { return }
            let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isVerticallyCentered = false
            [36.0].forEach { info.leftMargin = $0; info.rightMargin = $0; info.topMargin = $0; info.bottomMargin = $0 }
            let width = info.paperSize.width - info.leftMargin - info.rightMargin

            let printLayout = RichLayoutManager()
            printLayout.codeBlocks = source.codeBlocks
            printLayout.headingRanges = source.headingRanges
            printLayout.checkboxRanges = source.checkboxRanges
            printLayout.listPrefixRanges = source.listPrefixRanges
            printLayout.tableRanges = source.tableRanges
            let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            printLayout.addTextContainer(container)
            storage.addLayoutManager(printLayout)

            let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100), textContainer: container)
            printView.appearance = NSAppearance(named: .aqua)
            printView.backgroundColor = Theme.bgPage
            printView.drawsBackground = true
            printLayout.ensureLayout(for: container)
            printView.frame.size.height = printLayout.usedRect(for: container).height + 20

            let operation = NSPrintOperation(view: printView, printInfo: info)
            operation.jobTitle = window.title
            // Synchronous: returns once printed or cancelled, then the extra layout manager is detached
            operation.run()
            storage.removeLayoutManager(printLayout)
        }

        private func refreshImages(_ url: URL?) {
            guard let storage = textView?.textStorage, let layoutManager else { return }
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard let attachment = value as? ImageAttachment, url == nil || attachment.source == url else { return }
                layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.invalidateDisplay(forCharacterRange: range)
            }
        }

        /// No fixed debounce: while one render is in flight, later edits collapse into a single
        /// follow-up render, so preview latency equals render time rather than an arbitrary delay.
        func request(_ markdown: String, folder: URL?, documentID: UUID) {
            if documentID != self.documentID {
                if let previous = self.documentID, let clip = textView?.enclosingScrollView?.contentView {
                    scrollPositions[previous] = clip.bounds.origin
                }
                self.documentID = documentID
                pendingScroll = scrollPositions[documentID] ?? .zero
            }
            guard markdown != lastRequested || folder != self.folder else { return }
            lastRequested = markdown
            self.folder = folder
            pending = markdown
            guard !isRendering else { return }
            isRendering = true
            Task { await drain() }
        }

        private func drain() async {
            while let markdown = pending {
                pending = nil
                let document = await PreviewRenderer.document(for: markdown, folder: folder)
                apply(document)
            }
            isRendering = false
        }


        private func apply(_ document: RenderedDocument) {
            guard let textView, let layoutManager, let storage = textView.textStorage else { return }
            let clip = textView.enclosingScrollView?.contentView
            let scrollOrigin = clip?.bounds.origin

            layoutManager.codeBlocks       = document.codeBlocks
            layoutManager.headingRanges    = document.headingRanges
            layoutManager.checkboxRanges   = document.checkboxRanges
            layoutManager.listPrefixRanges = document.listPrefixRanges
            layoutManager.tableRanges      = document.tableRanges

            // Swap only the chunks that changed: keeps layout for the rest of the document
            // and avoids re-storing a whole large file on every keystroke
            let diff = RenderedDocument.changedRange(from: applied?.segments ?? [], to: document.segments)
            if applied == nil || diff.old.upperBound > storage.length {
                storage.setAttributedString(document.text)
                // First document: give the preview focus so ⌘F and keyboard scrolling act on it
                if applied == nil { textView.window?.makeFirstResponder(textView) }
            } else if diff.old.length > 0 || diff.new.length > 0 {
                storage.replaceCharacters(in: diff.old, with: document.text.attributedSubstring(from: diff.new))
            }
            applied = document

            // A reload keeps the reader's place; a tab switch goes to that tab's own place
            if let clip, let target = pendingScroll ?? scrollOrigin {
                if pendingScroll != nil { layoutManager.ensureLayout(forBoundingRect: CGRect(origin: target, size: clip.bounds.size), in: textView.textContainer!) }
                clip.scroll(to: target)
                textView.enclosingScrollView?.reflectScrolledClipView(clip)
            }
            pendingScroll = nil
            // Decorations are keyed to ranges, not text, so stale drawing must be cleared
            textView.needsDisplay = true
        }
    }
}
