import AppKit
import Markdown

/// Everything the preview needs to display one document. Immutable once built, so it can be
/// produced on a background thread and handed to the main thread exactly once.
nonisolated struct RenderedDocument: @unchecked Sendable {
    let text: NSAttributedString
    let codeBlocks: [CodeBlockInfo]
    let headingRanges: [(range: NSRange, level: Int)]
    let checkboxRanges: [(range: NSRange, isDone: Bool)]
    let listPrefixRanges: [(range: NSRange, nested: Bool)]
    let tableRanges: [NSRange]
    /// Which chunk produced each span of `text`, so a re-render can replace only what changed.
    var segments: [Segment] = []

    struct Segment: Equatable {
        let key: ContentKey   // the chunk's markdown; equal keys render identically
        var length: Int
    }
}

extension RenderedDocument {
    /// Joins independently rendered chunks, shifting every range by its chunk's offset.
    init(concatenating parts: [RenderedDocument]) {
        let text = NSMutableAttributedString()
        var codeBlocks: [CodeBlockInfo] = []
        var headings: [(range: NSRange, level: Int)] = []
        var checkboxes: [(range: NSRange, isDone: Bool)] = []
        var prefixes: [(range: NSRange, nested: Bool)] = []
        var tables: [NSRange] = []
        var segments: [Segment] = []

        for part in parts {
            // Every block ends in "\n"; guard anyway so a chunk can never run into the next one
            if text.length > 0, text.mutableString.character(at: text.length - 1) != 0x0A {
                text.append(NSAttributedString(string: "\n"))
                if !segments.isEmpty { segments[segments.count - 1].length += 1 }   // the break belongs to the chunk it ends
            }
            let offset = text.length
            let shift = { (r: NSRange) in NSRange(location: r.location + offset, length: r.length) }
            text.append(part.text)
            codeBlocks += part.codeBlocks.map { CodeBlockInfo(range: shift($0.range), language: $0.language) }
            headings   += part.headingRanges.map { (shift($0.range), $0.level) }
            checkboxes += part.checkboxRanges.map { (shift($0.range), $0.isDone) }
            prefixes   += part.listPrefixRanges.map { (shift($0.range), $0.nested) }
            tables     += part.tableRanges.map(shift)
            segments   += part.segments
        }
        self.init(text: text, codeBlocks: codeBlocks, headingRanges: headings,
                  checkboxRanges: checkboxes, listPrefixRanges: prefixes, tableRanges: tables,
                  segments: segments)
    }

    /// The span that differs between two renders, found by matching whole chunks from both ends.
    static func changedRange(from old: [Segment], to new: [Segment]) -> (old: NSRange, new: NSRange) {
        let prefix = zip(old, new).prefix { $0 == $1 }.count
        let maxSuffix = min(old.count, new.count) - prefix
        let suffix = zip(old.reversed(), new.reversed()).prefix(maxSuffix).prefix { $0 == $1 }.count
        let start = old.prefix(prefix).map(\.length).reduce(0, +)
        let length = { (segs: [Segment]) in segs.dropFirst(prefix).dropLast(suffix).map(\.length).reduce(0, +) }
        return (NSRange(location: start, length: length(old)), NSRange(location: start, length: length(new)))
    }
}

/// Markdown identity by exact UTF-8 bytes. Swift's String hashing and == Unicode-normalise
/// non-ASCII text character by character, which made cache lookups on large documents slow.
nonisolated struct ContentKey: Hashable, Sendable {
    let bytes: [UInt8]
    private let hash: Int   // precomputed: dictionaries rehash on growth

    init(_ text: String) {
        bytes = Array(text.utf8)
        var hasher = Hasher()
        bytes.withUnsafeBytes { hasher.combine(bytes: $0) }
        hash = hasher.finalize()
    }

    func hash(into hasher: inout Hasher) { hasher.combine(hash) }
    static func == (a: ContentKey, b: ContentKey) -> Bool { a.hash == b.hash && a.bytes == b.bytes }
}

/// Rendered chunks keyed by their exact markdown. Typing in a large document only changes one
/// chunk, so every other chunk is reused; switching back to a tab re-renders nothing.
nonisolated final class ChunkCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ContentKey: RenderedDocument] = [:]
    private var insertionOrder: [ContentKey] = []
    private var cachedBytes = 0
    private let byteLimit = 8 << 20   // markdown bytes (~7× that in rendered text); a few large documents

    func document(for key: ContentKey, render: () -> RenderedDocument) -> RenderedDocument {
        if let hit = lock.withLock({ entries[key] }) { return hit }
        let document = render()
        lock.withLock {
            guard entries[key] == nil else { return }
            entries[key] = document
            insertionOrder.append(key)
            cachedBytes += key.bytes.count
            while cachedBytes > byteLimit, !insertionOrder.isEmpty {
                let evicted = insertionOrder.removeFirst()
                cachedBytes -= evicted.bytes.count
                entries[evicted] = nil
            }
        }
        return document
    }
}

/// Markdown → styled attributed string. Pure and nonisolated so it runs off the main thread.
nonisolated enum PreviewRenderer {

    private static let cache = ChunkCache()
    private static let linkDefinitionRegex = try! NSRegularExpression(pattern: #"(?m)^ {0,3}\[[^\]\n]+\]:[ \t]*\S.*$"#)
    private static let footnoteDefinitionRegex = try! NSRegularExpression(pattern: #"^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)$"#)
    private static let footnoteReferenceRegex = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\](?!:)"#)
    private static let inFlightLock = NSLock()
    nonisolated(unsafe) private static var inFlight: [ContentKey: Task<RenderedDocument, Never>] = [:]

    /// Starts rendering as soon as a file is read, overlapping the time SwiftUI spends building
    /// the window; the preview then awaits the same in-flight render instead of starting another.
    static func prefetch(_ markdown: String, folder: URL?) {
        Task.detached(priority: .userInitiated) { _ = await document(for: markdown, folder: folder) }
    }

    static func document(for markdown: String, folder: URL?) async -> RenderedDocument {
        let key = cacheKey(markdown, folder: folder)
        let task = inFlightLock.withLock {
            if let running = inFlight[key] { return running }
            let started = Task.detached(priority: .userInitiated) { render(markdown, folder: folder) }
            inFlight[key] = started
            return started
        }
        let document = await task.value
        inFlightLock.withLock { inFlight[key] = nil }
        return document
    }

    /// Large documents are split at headings and the chunks rendered in parallel (and cached),
    /// so render cost scales with cores on first open and with the edited chunk while typing.
    /// 4 KB chunks measured fastest: parallelism plus per-chunk passes that scale worse than linearly.
    static func render(_ markdown: String, folder: URL? = nil, targetSize: Int = 4_096) -> RenderedDocument {
        // Footnotes are numbered across the whole document, so they resolve before it is split
        let markdown = resolveFootnotes(in: markdown)
        let parts = chunks(of: markdown, targetSize: targetSize)
        guard parts.count > 1 else { return cachedChunk(markdown, folder: folder) }

        // A reference definition applies document-wide, but each chunk is parsed alone
        let definitions = linkReferenceDefinitions(in: markdown)
        let suffix = definitions.isEmpty ? "" : "\n\n" + definitions.joined(separator: "\n") + "\n"

        var rendered = [RenderedDocument?](repeating: nil, count: parts.count)
        rendered.withUnsafeMutableBufferPointer { slots in
            DispatchQueue.concurrentPerform(iterations: parts.count) { i in
                slots[i] = cachedChunk(parts[i] + suffix, folder: folder)
            }
        }
        return RenderedDocument(concatenating: rendered.map { $0! })
    }

    /// The folder changes what relative links and images point at, so it is part of the identity
    private static func cacheKey(_ markdown: String, folder: URL?) -> ContentKey {
        ContentKey(folder.map { markdown + "\u{0}" + $0.path } ?? markdown)
    }

    private static func cachedChunk(_ markdown: String, folder: URL?) -> RenderedDocument {
        let key = cacheKey(markdown, folder: folder)
        return cache.document(for: key) { renderChunk(markdown, folder: folder, key: key) }
    }

    /// Splits before ATX headings outside code fences, once a chunk reaches `targetSize` UTF-8 bytes.
    /// A heading always starts a fresh block, so each chunk parses exactly as it would in place.
    static func chunks(of markdown: String, targetSize: Int) -> [String] {
        let bytes = Array(markdown.utf8)   // byte scanning: NSString character access was the bottleneck
        guard bytes.count > targetSize else { return [markdown] }

        let space = UInt8(ascii: " "), hash = UInt8(ascii: "#"), newline = UInt8(ascii: "\n")
        let byte = { (i: Int) -> UInt8 in i < bytes.count ? bytes[i] : newline }

        var cuts: [Int] = []
        var chunkStart = 0, lineStart = 0
        var inFence = false
        while lineStart < bytes.count {
            var i = lineStart
            while i < lineStart + 3, byte(i) == space { i += 1 }

            let first = byte(i)
            let isFence = (first == UInt8(ascii: "`") || first == UInt8(ascii: "~")) && byte(i + 1) == first && byte(i + 2) == first
            var hashes = 0
            while byte(i + hashes) == hash { hashes += 1 }
            let isHeading = (1...6).contains(hashes) && [space, UInt8(ascii: "\t"), newline, UInt8(ascii: "\r")].contains(byte(i + hashes))

            if isFence {
                inFence.toggle()
            } else if isHeading, !inFence, lineStart - chunkStart >= targetSize {
                cuts.append(lineStart)
                chunkStart = lineStart
            }
            lineStart = (bytes[lineStart...].firstIndex(of: newline) ?? bytes.count - 1) + 1
        }
        // Cuts sit at line starts after "\n", so every slice is valid UTF-8
        return zip([0] + cuts, cuts + [bytes.count]).map { String(decoding: bytes[$0..<$1], as: UTF8.self) }
    }

    static func linkReferenceDefinitions(in markdown: String) -> [String] {
        // Byte pre-scan for lines shaped like "[label]:" — running the regex over a bridged
        // 1 MB String on every keystroke cost ~8 ms; only candidate lines are checked by regex
        let bytes = Array(markdown.utf8)
        let open = UInt8(ascii: "["), close = UInt8(ascii: "]"), colon = UInt8(ascii: ":"), newline = UInt8(ascii: "\n")
        var candidates: [String] = []
        var lineStart = 0
        while lineStart < bytes.count {
            let lineEnd = bytes[lineStart...].firstIndex(of: newline) ?? bytes.count
            var i = lineStart
            while i < min(lineStart + 3, lineEnd), bytes[i] == UInt8(ascii: " ") { i += 1 }
            if i < lineEnd, bytes[i] == open,
               let closing = bytes[i..<lineEnd].firstIndex(of: close), closing + 1 < lineEnd, bytes[closing + 1] == colon {
                candidates.append(String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self))
            }
            lineStart = lineEnd + 1
        }
        return candidates.filter { line in
            linkDefinitionRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }

    /// `[^id]` references become numbered markers (U+E000 n U+E001, styled as superscripts by the
    /// builder) and their definitions move into a numbered list at the end. swift-markdown has no
    /// footnote support. Numbers follow first reference, like GitHub; code fences are left alone.
    static func resolveFootnotes(in markdown: String) -> String {
        guard markdown.contains("[^") else { return markdown }
        var definitions: [String: String] = [:]
        var kept: [String] = []
        var inFence = false
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            let ns = line as NSString
            if !inFence, let match = footnoteDefinitionRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                definitions[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2))
            } else {
                kept.append(line)
            }
        }
        guard !definitions.isEmpty else { return markdown }

        var numbers: [String: Int] = [:]
        inFence = false
        let body = kept.map { line -> String in
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); return line }
            guard !inFence, line.contains("[^") else { return line }
            let ns = line as NSString
            var result = ""
            var cursor = 0
            for match in footnoteReferenceRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let id = ns.substring(with: match.range(at: 1))
                guard definitions[id] != nil else { continue }
                let number = numbers[id] ?? { numbers[id] = numbers.count + 1; return numbers.count }()
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result += InlineScanner.footnoteOpen + "\(number)" + InlineScanner.footnoteClose
                cursor = match.range.upperBound
            }
            return result + ns.substring(from: cursor)
        }.joined(separator: "\n")

        let notes = numbers.sorted { $0.value < $1.value }.map { "\($0.value). \(definitions[$0.key]!)" }
        return notes.isEmpty ? body : body + "\n\n---\n\n" + notes.joined(separator: "\n") + "\n"
    }

    static func renderChunk(_ content: String, folder: URL? = nil, key: ContentKey? = nil) -> RenderedDocument {
        var builder = MarkdownBuilder(documentFolder: folder)
        builder.build(content)
        let text = highlighted(builder.output, codeBlocks: builder.codeBlocks)
        return RenderedDocument(
            text: text,
            codeBlocks: builder.codeBlocks,
            headingRanges: builder.headings,
            checkboxRanges: builder.checkboxes,
            listPrefixRanges: builder.listPrefixes,
            tableRanges: builder.tables,
            segments: [RenderedDocument.Segment(key: key ?? cacheKey(content, folder: folder), length: text.length)]
        )
    }

    // MARK: - Syntax highlighting

    private static func highlighted(_ input: NSMutableAttributedString, codeBlocks: [CodeBlockInfo]) -> NSMutableAttributedString {
        // Code blocks are always dark, so adaptive token colors must be pinned to their dark variant
        let darkVariant = { (color: NSColor) -> NSColor in
            var resolved = color
            NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
                resolved = color.usingColorSpace(.deviceRGB) ?? color
            }
            return resolved
        }
        for block in codeBlocks {
            let codeText = (input.string as NSString).substring(with: block.range)
            for token in SyntaxHighlighter.tokenize(codeText, language: block.language) {
                let r = NSRange(location: block.range.location + token.nsRange.location, length: token.nsRange.length)
                guard r.upperBound <= input.length else { continue }
                input.addAttribute(.foregroundColor, value: darkVariant(token.color), range: r)
            }
        }
        return input
    }

    // MARK: - Status badges

    enum StatusBadge: Equatable {
        case ok(String)
        case warn(String)
    }

    /// Status words become badges; emoji decorations ("✅ OK") are dropped since the design uses none.
    static func statusBadge(for cellText: String) -> StatusBadge? {
        // Only strip pictographs: ASCII digits/#/* also carry the isEmoji property (keycap bases)
        let word = String(String.UnicodeScalarView(cellText.unicodeScalars.filter {
            !($0.properties.isEmoji && $0.value > 0x7F) && $0.value != 0xFE0F
        })).trimmingCharacters(in: .whitespaces)

        switch word.lowercased() {
        case "active", "ok", "done", "pass", "passing":            return .ok(word.uppercased())
        case "review", "warn", "warning", "error", "fail", "failing": return .warn(word.uppercased())
        default:                                                     return nil
        }
    }
}
