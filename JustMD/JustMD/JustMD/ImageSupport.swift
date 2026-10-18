import AppKit
import Combine

// MARK: - Loading

/// Loads and caches images for every open document. Layout asks for an image's state, and the first
/// ask starts the load; when it finishes, observers re-layout the attachments that show it.
nonisolated final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()
    /// Posted on the main queue; `object` is the image URL, or nil when many changed at once
    static let didChange = Notification.Name("JustMDImageStoreDidChange")

    enum State {
        case loading
        case loaded(NSImage)
        case failed
    }

    private let lock = NSLock()
    private var states: [URL: State] = [:]
    private static let maxBytes = 25 << 20

    func state(for url: URL) -> State? { lock.withLock { states[url] } }

    func request(_ url: URL) {
        let isNew = lock.withLock {
            guard states[url] == nil else { return false }
            states[url] = .loading
            return true
        }
        guard isNew else { return }
        Task.detached(priority: .utility) { [self] in
            let image = await Self.load(url)
            lock.withLock { states[url] = image.map(State.loaded) ?? .failed }
            await MainActor.run { NotificationCenter.default.post(name: Self.didChange, object: url) }
        }
    }

    /// After the user grants a folder, images in it that failed (sandbox) get another try
    func forgetFailures(under folder: URL) {
        lock.withLock {
            states = states.filter { url, state in
                guard case .failed = state else { return true }
                return !FolderAccess.path(url.path, isInside: folder.path)
            }
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    private static func load(_ url: URL) async -> NSImage? {
        // Local files and inline data: URLs are read directly; nothing touches the network
        if url.isFileURL || url.scheme?.lowercased() == "data" {
            return (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap(NSImage.init(data:))
        }
        guard ["http", "https"].contains(url.scheme?.lowercased()),
              let result = try? await URLSession.shared.data(from: url),
              (result.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              result.0.count <= maxBytes else { return nil }
        return NSImage(data: result.0)
    }
}

// MARK: - Attachment

/// An image in the preview. Its cell sizes itself from the shared store, so the same attachment shows
/// a placeholder, then the image, without re-rendering the document.
nonisolated final class ImageAttachment: NSTextAttachment {
    let source: URL
    let alt: String

    init(source: URL, alt: String) {
        self.source = source
        self.alt = alt
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { nil }

    // Cells are AppKit (main-actor) objects: made on first use during layout, never in the background renderer
    private var cell: ImageAttachmentCell?
    override var attachmentCell: (any NSTextAttachmentCellProtocol)? {
        get {
            MainActor.assumeIsolated {
                if cell == nil { cell = ImageAttachmentCell(attachment: self) }
                return cell
            }
        }
        set {}
    }

    /// Wide images shrink to the column keeping their aspect; small ones keep their natural size
    static func fittedSize(natural: CGSize, available: CGFloat) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return CGSize(width: 1, height: 1) }
        let width = min(natural.width, max(available, 1))
        return CGSize(width: width.rounded(), height: max(1, (natural.height * width / natural.width).rounded()))
    }
}

private final class ImageAttachmentCell: NSTextAttachmentCell {
    private weak var imageAttachment: ImageAttachment?

    init(attachment: ImageAttachment) {
        imageAttachment = attachment
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) { super.init(coder: coder) }

    private var loadedImage: NSImage? {
        guard let source = imageAttachment?.source else { return nil }
        ImageStore.shared.request(source)
        if case .loaded(let image) = ImageStore.shared.state(for: source) { return image }
        return nil
    }

    // Declared nonisolated by the protocol; TextKit only calls it during layout, on the main thread
    nonisolated override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                                        glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        MainActor.assumeIsolated {
            guard let image = loadedImage else {
                let size = placeholderSize
                return NSRect(x: 0, y: -7, width: size.width, height: size.height)
            }
            let available = lineFrag.width - position.x - textContainer.lineFragmentPadding
            return NSRect(origin: .zero, size: ImageAttachment.fittedSize(natural: image.size, available: available))
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                       layoutManager: NSLayoutManager) {
        if let image = loadedImage {
            image.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            drawPlaceholder(in: cellFrame)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        drawPlaceholder(in: cellFrame)
    }

    // MARK: Placeholder: a quiet box with an image glyph and the alt text

    private var label: NSAttributedString {
        let text = imageAttachment.map { $0.alt.isEmpty ? $0.source.lastPathComponent : $0.alt } ?? ""
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.textMuted,
        ])
    }

    private var placeholderSize: NSSize {
        NSSize(width: min(label.size().width, 360) + 44, height: 26)
    }

    private func drawPlaceholder(in frame: NSRect) {
        let box = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        Theme.textMuted.withAlphaComponent(0.08).setFill()
        box.fill()
        Theme.textMuted.withAlphaComponent(0.35).setStroke()
        box.stroke()
        if let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular).applying(.init(hierarchicalColor: Theme.textMuted))) {
            symbol.draw(in: NSRect(x: frame.minX + 10, y: frame.midY - 7, width: 16, height: 14),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        label.draw(with: NSRect(x: frame.minX + 32, y: frame.midY - 8, width: frame.width - 40, height: 16),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

// MARK: - Local references and folder access

/// Finds the local images a document refers to, so JustMD can ask for the folder they live in.
nonisolated enum LocalImages {
    private static let markdownImage = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)"#)
    private static let inlineCode = try! NSRegularExpression(pattern: #"`[^`\n]*`"#)

    static func references(in markdown: String) -> [String] {
        let prose = withoutCode(markdown)
        let ns = prose as NSString
        let markdownSources = markdownImage.matches(in: prose, range: NSRange(location: 0, length: ns.length)).map { match in
            ns.substring(with: match.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }
        let htmlSources = HTMLText.images(in: prose).map(\.source)
        return (markdownSources + htmlSources).filter { source in
            let lower = source.lowercased()
            return !["http://", "https://", "data:", "//"].contains { lower.hasPrefix($0) }
        }
    }

    /// The folder to ask the user for, or nil when every local image is already readable
    static func folderNeedingAccess(markdown: String, documentFolder: URL, isReadable: (URL) -> Bool) -> URL? {
        let unreadable = references(in: markdown)
            .map { resolve($0, in: documentFolder) }
            .filter { !isReadable($0) }
        guard !unreadable.isEmpty else { return nil }
        // Widen to the common ancestor when images live outside the document's own folder (../assets)
        let paths = [documentFolder.standardizedFileURL.pathComponents]
            + unreadable.map { $0.deletingLastPathComponent().standardizedFileURL.pathComponents }
        let common = paths.dropFirst().reduce(paths[0]) { shared, next in Array(zip(shared, next).prefix { $0 == $1 }.map(\.0)) }
        return URL(fileURLWithPath: NSString.path(withComponents: common), isDirectory: true)
    }

    static func resolve(_ source: String, in folder: URL) -> URL {
        let path = source.removingPercentEncoding ?? source
        return URL(fileURLWithPath: path, relativeTo: folder).standardizedFileURL
    }

    private static func withoutCode(_ markdown: String) -> String {
        var inFence = false
        let lines = markdown.components(separatedBy: "\n").filter { line in
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); return false }
            return !inFence
        }
        let joined = lines.joined(separator: "\n")
        return inlineCode.stringByReplacingMatches(in: joined, range: NSRange(location: 0, length: (joined as NSString).length), withTemplate: "")
    }
}

/// Folders the user has let JustMD read (for images beside documents). Granted through an open panel,
/// remembered as security-scoped bookmarks and re-opened at launch.
@MainActor
final class FolderAccess: ObservableObject {
    @Published private(set) var folders: [URL] = []
    private let storePath: URL
    private var bookmarks: [String: Data] = [:]

    init(storePath: URL = FolderAccess.defaultStorePath) {
        self.storePath = storePath
        guard let data = try? Data(contentsOf: storePath),
              let stored = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return }
        for (_, bookmark) in stored {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            folders.append(url.standardizedFileURL)
            bookmarks[url.standardizedFileURL.path] = bookmark
        }
    }

    func grant(_ folder: URL) {
        let folder = folder.standardizedFileURL
        guard !folders.contains(folder) else { return }
        _ = folder.startAccessingSecurityScopedResource()
        if let bookmark = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[folder.path] = bookmark
            try? FileManager.default.createDirectory(at: storePath.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? PropertyListEncoder().encode(bookmarks).write(to: storePath, options: .atomic)
        }
        folders.append(folder)
    }

    func covers(_ url: URL) -> Bool {
        folders.contains { Self.path(url.standardizedFileURL.path, isInside: $0.path) }
    }

    nonisolated static func path(_ path: String, isInside folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    nonisolated static var defaultStorePath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JustMD/folders.plist")
    }
}
