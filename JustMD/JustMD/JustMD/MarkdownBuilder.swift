import AppKit
import Markdown

/// Walks a swift-markdown syntax tree and produces the styled text plus the range metadata
/// `RichLayoutManager` draws from. Every block ends in "\n", so independently rendered chunks
/// concatenate exactly as one document would.
nonisolated struct MarkdownBuilder {
    private(set) var output = NSMutableAttributedString()
    private(set) var codeBlocks: [CodeBlockInfo] = []
    private(set) var headings: [(range: NSRange, level: Int)] = []
    private(set) var checkboxes: [(range: NSRange, isDone: Bool)] = []
    private(set) var listPrefixes: [(range: NSRange, nested: Bool)] = []
    private(set) var tables: [NSRange] = []

    private let documentFolder: URL?
    private var indent: CGFloat = 0          // accumulated list + quote indentation
    private var quoteDepth = 0
    private var listDepth = 0
    private var pendingItem: PendingItem?    // prefix waiting for the item's first paragraph
    private var lastParagraph: NSRange?

    private struct PendingItem {
        let prefix: String
        let ordered: Bool
        let checkbox: Checkbox?
        let contentIndent: CGFloat
    }

    // Layout constants, carried over from the previous Down-based styling
    private static let listStep: CGFloat = 26
    private static let quoteStep: CGFloat = 17
    private static let codeInset: CGFloat = 14
    private static let bodyFont = NSFont.systemFont(ofSize: 15)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let headingFonts: [NSFont] = [
        .systemFont(ofSize: 42, weight: .bold), .systemFont(ofSize: 32, weight: .bold),
        .systemFont(ofSize: 26, weight: .semibold), .systemFont(ofSize: 21, weight: .semibold),
        .systemFont(ofSize: 18, weight: .medium), .systemFont(ofSize: 16, weight: .medium),
    ]
    private static let headingSpaceBefore: [CGFloat] = [36, 28, 22, 18, 14, 12]

    init(documentFolder: URL?) {
        self.documentFolder = documentFolder
    }

    mutating func build(_ markdown: String) {
        let document = Document(parsing: markdown, options: [.disableSmartOpts, .disableSourcePosOpts])
        document.children.forEach { block($0) }
    }

    // MARK: - Blocks

    private mutating func block(_ node: Markup) {
        switch node {
        case let heading as Heading:        self.heading(heading)
        case let paragraph as Paragraph:    self.paragraph(paragraph)
        case let code as CodeBlock:         codeBlock(code.code, language: code.language)
        case let quote as BlockQuote:       blockQuote(quote)
        case let list as UnorderedList:     self.list(Array(list.listItems), start: nil)
        case let list as OrderedList:       self.list(Array(list.listItems), start: Int(list.startIndex))
        case is ThematicBreak:              thematicBreak()
        case let table as Table:            self.table(table)
        case let html as HTMLBlock:         htmlBlock(html.rawHTML)
        default:                            node.children.forEach { block($0) }
        }
    }

    private mutating func heading(_ node: Heading) {
        let level = min(max(node.level, 1), 6)
        let font = Self.headingFonts[level - 1]
        let style = paragraphStyle(lineHeight: 1.15, before: Self.headingSpaceBefore[level - 1], after: level == 1 ? 20 : 6)
        let color: NSColor = switch level {
            case 1: .clear   // RichLayoutManager paints the gradient through the glyph outlines
            case 2: Theme.textH2
            case 3: Theme.textH3
            case 6: Theme.textMuted
            default: Theme.textHeading
        }
        let text = inlines(node, base: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        if level == 3 { uppercase(text) }
        let kern: CGFloat = level == 3 ? 0.5 : font.pointSize >= 28 ? -0.6 : font.pointSize >= 20 ? -0.3 : 0
        if kern != 0 { text.addAttribute(.kern, value: kern, range: NSRange(location: 0, length: text.length)) }
        let range = append(text)
        headings.append((range, level))
        appendNewline(style: style, font: font)
    }

    private mutating func paragraph(_ node: Paragraph) {
        var base: [NSAttributedString.Key: Any] = [.font: Self.bodyFont, .foregroundColor: Theme.textBody]
        let start = output.length

        if let item = pendingItem {
            pendingItem = nil
            let style = listItemStyle(contentIndent: item.contentIndent)
            base[.paragraphStyle] = style
            appendListPrefix(item, style: style)
            if item.checkbox == .checked {
                base[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                base[.foregroundColor] = Theme.textMuted
            }
        } else if listDepth > 0 {
            base[.paragraphStyle] = paragraphStyle(lineHeight: 1.2, before: 3, after: 3, head: indent)
        } else {
            base[.paragraphStyle] = paragraphStyle(lineHeight: 1.65, after: 14, head: indent)
        }

        append(inlines(node, base: base))
        appendNewline(style: base[.paragraphStyle] as! NSParagraphStyle, font: Self.bodyFont)
        let range = NSRange(location: start, length: output.length - start)
        markQuote(range)
        lastParagraph = range
    }

    private mutating func appendListPrefix(_ item: PendingItem, style: NSParagraphStyle) {
        let prefixAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.bodyFont, .paragraphStyle: style,
            // Bullets are drawn as custom dots; numbers carry meaning, so they stay visible
            .foregroundColor: item.ordered ? Theme.accentPrimary : NSColor.clear,
        ]
        let prefixRange = append(NSAttributedString(string: item.prefix, attributes: prefixAttrs))
        append(NSAttributedString(string: "\t", attributes: prefixAttrs))
        if !item.ordered, item.checkbox == nil { listPrefixes.append((prefixRange, listDepth > 1)) }

        if let checkbox = item.checkbox {
            // Transparent placeholder: RichLayoutManager draws the box; kern makes room for it
            let box = append(NSAttributedString(string: checkbox == .checked ? "\u{2611}" : "\u{2610}", attributes: [
                .font: Self.bodyFont, .paragraphStyle: style, .foregroundColor: NSColor.clear, .kern: 10,
            ]))
            checkboxes.append((box, checkbox == .checked))
        }
    }

    private mutating func list(_ items: [ListItem], start: Int?) {
        listDepth += 1
        defer { listDepth -= 1 }
        for (offset, item) in items.enumerated() {
            pendingItem = PendingItem(
                prefix: start.map { "\($0 + offset)." } ?? "\u{2022}",
                ordered: start != nil,
                checkbox: item.checkbox,
                contentIndent: indent + Self.listStep)
            indent += Self.listStep
            item.children.forEach { block($0) }
            indent -= Self.listStep
            pendingItem = nil
        }
        // The list as a whole gets the same space below it as a paragraph
        if listDepth == 1, let last = lastParagraph, last.upperBound == output.length {
            restyle(last) { $0.paragraphSpacing = 14 }
        }
    }

    private mutating func blockQuote(_ node: BlockQuote) {
        quoteDepth += 1
        indent += Self.quoteStep
        node.children.forEach { block($0) }
        indent -= Self.quoteStep
        quoteDepth -= 1
    }

    private mutating func codeBlock(_ code: String, language: String?) {
        let body = code.hasSuffix("\n") ? String(code.dropLast()) : code
        // Empty first line: the traffic-light header row lives there, clear of the code
        let lines = [""] + body.components(separatedBy: "\n")
        let start = output.length
        for (i, line) in lines.enumerated() {
            let style = paragraphStyle(lineHeight: 1.5,
                                       before: i == 0 ? 4 : 0, after: i == lines.count - 1 ? 18 : 0,
                                       head: indent + Self.codeInset, tail: -Self.codeInset)
            append(NSAttributedString(string: line + "\n", attributes: [
                .font: Self.codeFont, .foregroundColor: Theme.codeText,
                .paragraphStyle: style, .codeBackground: Theme.bgCodeBlock,
            ]))
        }
        // Exclude the final newline so adjacent blocks never share a range
        let range = NSRange(location: start, length: output.length - start - 1)
        output.removeAttribute(.codeBackground, range: NSRange(location: range.upperBound, length: 1))
        let lang = language?.split(separator: " ").first.map { $0.lowercased() }
        codeBlocks.append(CodeBlockInfo(range: range, language: lang?.isEmpty == false ? lang : nil))
    }

    private mutating func thematicBreak() {
        append(NSAttributedString(string: "\n", attributes: [
            .font: Self.bodyFont,
            .paragraphStyle: paragraphStyle(lineHeight: 1.65, before: 6, after: 6, head: indent),
            .thematicBreakColor: Theme.textMuted,
        ]))
    }

    private mutating func htmlBlock(_ html: String) {
        // Images inside HTML (centred logos in READMEs) render; other markup is reduced to its text
        let images = HTMLText.images(in: html)
        let text = HTMLText.strip(html)
        guard !images.isEmpty || !text.isEmpty else { return }
        let style = paragraphStyle(lineHeight: 1.65, after: 14, head: indent, alignment: HTMLText.isCentered(html) ? .center : .natural)
        let base: [NSAttributedString.Key: Any] = [.font: Self.bodyFont, .foregroundColor: Theme.textBody, .paragraphStyle: style]
        let paragraph = NSMutableAttributedString()
        images.forEach { paragraph.append(image(source: $0.source, alt: $0.alt, attributes: base)) }
        if !text.isEmpty {
            if !images.isEmpty { paragraph.append(NSAttributedString(string: "\u{2028}", attributes: base)) }
            paragraph.append(NSAttributedString(string: text, attributes: base))
        }
        append(paragraph)
        appendNewline(style: style, font: Self.bodyFont)
    }

    // MARK: - Tables

    private mutating func table(_ node: Table) {
        let columns = max(node.maxColumnCount, 1)
        let nsTable = NSTextTable()
        nsTable.numberOfColumns = columns
        nsTable.collapsesBorders = false
        nsTable.hidesEmptyCells = true
        [NSTextBlock.Layer.margin, .border, .padding].forEach { nsTable.setWidth(0, type: .absoluteValueType, for: $0) }
        // Percentages reflow on resize without a re-render; fixed layout keeps columns equal
        nsTable.setContentWidth(100, type: .percentageValueType)
        nsTable.layoutAlgorithm = .fixedLayoutAlgorithm

        let alignments = node.columnAlignments
        let rows: [[Table.Cell]] = [Array(node.head.cells)] + node.body.rows.map { Array($0.cells) }
        let start = output.length
        for (rowIndex, cells) in rows.enumerated() {
            for column in 0..<columns {
                let cell = column < cells.count ? cells[column] : nil
                let alignment: NSTextAlignment = switch column < alignments.count ? alignments[column] : nil {
                    case .left?: .left
                    case .right?: .right
                    case .center?, nil: .center   // unspecified keeps the design's centred cells
                }
                append(tableCell(cell, table: nsTable, row: rowIndex, column: column, columns: columns, alignment: alignment))
            }
        }
        tables.append(NSRange(location: start, length: output.length - start))
    }

    private func tableCell(_ cell: Table.Cell?, table: NSTextTable, row: Int, column: Int, columns: Int,
                           alignment: NSTextAlignment) -> NSAttributedString {
        let isHeader = row == 0
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.backgroundColor = isHeader ? Theme.tableHeaderBg : (row % 2 == 1 ? Theme.tableBg : Theme.tableAltBg)
        [NSTextBlock.Layer.margin, .border].forEach { block.setWidth(0, type: .absoluteValueType, for: $0) }
        block.setWidth(0, type: .absoluteValueType, for: .padding)
        block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .maxX)
        block.setContentWidth(100 / CGFloat(columns), type: .percentageValueType)
        block.verticalAlignment = .middleAlignment

        let style = NSMutableParagraphStyle()
        style.textBlocks = [block]
        style.alignment = alignment
        let fontSize: CGFloat = isHeader ? 22 : 16
        // Spacing approximates vertical centring (TextKit 1's middleAlignment is unreliable)
        style.paragraphSpacingBefore = fontSize * 0.55
        style.paragraphSpacing = fontSize * 0.55

        let base: [NSAttributedString.Key: Any] = [
            .paragraphStyle: style,
            .font: isHeader ? NSFont.systemFont(ofSize: 22, weight: .bold) : NSFont.systemFont(ofSize: 16),
            .foregroundColor: isHeader ? Theme.tableHeaderFg : Theme.textBody,
        ]
        let content = cell.map { inlines($0, base: base) } ?? NSMutableAttributedString()
        if !isHeader, let badge = PreviewRenderer.statusBadge(for: content.string) {
            return badgeText(badge, style: style)
        }
        if isHeader { uppercase(content) }
        content.append(NSAttributedString(string: "\n", attributes: base))
        return content
    }

    private func badgeText(_ badge: PreviewRenderer.StatusBadge, style: NSParagraphStyle) -> NSAttributedString {
        let (label, accent): (String, NSColor) = switch badge {
            case .ok(let word): (word, Theme.accentPrimary)
            case .warn(let word): (word, Theme.accentSecondary)
        }
        let text = NSMutableAttributedString(string: " \(label) ", attributes: [
            .paragraphStyle: style,
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .bold),
            .foregroundColor: accent,
            .backgroundColor: accent.withAlphaComponent(0.12),
        ])
        // A newline's background fills to the end of the line, so the terminator gets none
        text.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        return text
    }

    // MARK: - Inlines

    struct InlineStyle {
        var bold = false, italic = false, strike = false, code = false
        var underline = false, highlight = false
        var superscript = false, subscript_ = false
        var link: URL?
    }

    private func inlines(_ container: Markup, base: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        appendInlines(of: container, style: InlineStyle(), base: base, into: result)
        return result
    }

    private func appendInlines(of container: Markup, style: InlineStyle,
                               base: [NSAttributedString.Key: Any], into result: NSMutableAttributedString) {
        var current = style       // inline HTML tags (<b>…</b>) toggle style across siblings
        var pendingText = ""      // adjacent text nodes merge so URLs split by the parser stay whole

        func flush() {
            guard !pendingText.isEmpty else { return }
            result.append(styledText(pendingText, style: current, base: base))
            pendingText = ""
        }

        for child in container.children {
            switch child {
            case let text as Text:
                pendingText += text.string
            case is SoftBreak:
                pendingText += " "
            case is LineBreak:
                pendingText += "\u{2028}"
            case let code as InlineCode:
                flush()
                var codeStyle = current
                codeStyle.code = true
                result.append(attributed(code.code, style: codeStyle, base: base))
            case let emphasis as Emphasis:
                flush()
                var s = current; s.italic = true
                appendInlines(of: emphasis, style: s, base: base, into: result)
            case let strong as Strong:
                flush()
                var s = current; s.bold = true
                appendInlines(of: strong, style: s, base: base, into: result)
            case let strike as Strikethrough:
                flush()
                var s = current; s.strike = true
                appendInlines(of: strike, style: s, base: base, into: result)
            case let link as Link:
                flush()
                var s = current; s.link = link.destination.flatMap(resolve)
                appendInlines(of: link, style: s, base: base, into: result)
            case let image as Image:
                flush()
                result.append(self.image(source: image.source, alt: plainText(image), attributes: attributes(for: current, base: base)))
            case let html as InlineHTML:
                flush()
                switch HTMLText.inlineTag(html.rawHTML) {
                case .lineBreak:                 result.append(attributed("\u{2028}", style: current, base: base))
                case .image(let source, let alt): result.append(image(source: source, alt: alt, attributes: attributes(for: current, base: base)))
                case .toggle(let apply):         apply(&current)
                case nil:                        break   // unknown tags and comments render nothing
                }
            default:
                flush()
                appendInlines(of: child, style: current, base: base, into: result)
            }
        }
        flush()
    }

    /// Plain text runs: bare URLs become links and resolved footnote markers become superscripts
    private func styledText(_ text: String, style: InlineStyle, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let ns = text as NSString
        var cursor = 0
        let matches = style.link == nil && !style.code
            ? InlineScanner.matches(in: text)
            : InlineScanner.footnoteMatches(in: text)
        for match in matches {
            if match.range.location > cursor {
                result.append(attributed(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), style: style, base: base))
            }
            var s = style
            switch match.kind {
            case .url(let url):
                s.link = url
                result.append(attributed(ns.substring(with: match.range), style: s, base: base))
            case .footnote(let number):
                s.superscript = true
                let marker = attributed(number, style: s, base: base)
                let tinted = NSMutableAttributedString(attributedString: marker)
                tinted.addAttribute(.foregroundColor, value: Theme.accentPrimary, range: NSRange(location: 0, length: tinted.length))
                result.append(tinted)
            }
            cursor = match.range.upperBound
        }
        if cursor < ns.length {
            result.append(attributed(ns.substring(from: cursor), style: style, base: base))
        }
        return result
    }

    private func attributed(_ text: String, style: InlineStyle, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: text, attributes: attributes(for: style, base: base))
    }

    private func attributes(for style: InlineStyle, base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = base
        let baseFont = base[.font] as? NSFont ?? Self.bodyFont
        var font = baseFont
        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.bold { traits.insert(.bold) }
        if style.italic { traits.insert(.italic) }
        if !traits.isEmpty {
            font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)),
                          size: font.pointSize) ?? font
        }
        if style.code {
            font = .monospacedSystemFont(ofSize: max(11, (baseFont.pointSize * 0.87).rounded()), weight: style.bold ? .semibold : .regular)
            // Colour only: a background would fill the whole 1.65× line height as a tall slab
            attrs[.foregroundColor] = Theme.inlineCodeFg
        }
        if style.superscript || style.subscript_ {
            font = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * 0.72) ?? font
            attrs[.baselineOffset] = baseFont.pointSize * (style.superscript ? 0.38 : -0.18)
        }
        attrs[.font] = font
        if style.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.highlight { attrs[.backgroundColor] = Theme.accentSecondary.withAlphaComponent(0.18) }
        if let link = style.link { attrs[.link] = link }
        return attrs
    }

    private func plainText(_ node: Markup) -> String {
        node.children.map { child in
            switch child {
            case let text as Text: text.string
            case let code as InlineCode: code.code
            default: plainText(child)
            }
        }.joined()
    }

    /// Relative links resolve against the document's folder, so links between notes work
    private func resolve(_ destination: String) -> URL? {
        if let url = URL(string: destination), url.scheme != nil { return url }
        guard let folder = documentFolder else { return URL(string: destination) }
        return URL(string: destination, relativeTo: folder)?.absoluteURL
    }

    // MARK: - Images

    private func image(source: String?, alt: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard let source, let url = imageURL(source) else {
            // Unusable source (or a relative path with no document folder): keep the alt text visible
            var attrs = attributes
            attrs[.foregroundColor] = Theme.textMuted
            return NSAttributedString(string: "[\(alt.isEmpty ? "image" : alt)]", attributes: attrs)
        }
        let text = NSMutableAttributedString(attachment: ImageAttachment(source: url, alt: alt))
        // Paragraph style, font and any enclosing link carry over, so a linked image stays clickable
        text.addAttributes(attributes, range: NSRange(location: 0, length: text.length))
        return text
    }

    private func imageURL(_ source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https", "data"].contains(scheme) {
            return url
        }
        return documentFolder.map { LocalImages.resolve(trimmed, in: $0) }
    }

    // MARK: - Output helpers

    @discardableResult
    private mutating func append(_ text: NSAttributedString) -> NSRange {
        let start = output.length
        output.append(text)
        return NSRange(location: start, length: text.length)
    }

    private mutating func appendNewline(style: NSParagraphStyle, font: NSFont) {
        append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: style]))
    }

    private mutating func markQuote(_ range: NSRange) {
        guard quoteDepth > 0 else { return }
        output.addAttribute(.quoteStripeColor, value: Theme.accentPrimary, range: range)
        output.addAttribute(.quoteBackground, value: Theme.blockquoteBg, range: range)
    }

    private mutating func restyle(_ range: NSRange, _ change: (NSMutableParagraphStyle) -> Void) {
        guard let current = output.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
              let style = current.mutableCopy() as? NSMutableParagraphStyle else { return }
        change(style)
        output.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func uppercase(_ text: NSMutableAttributedString) {
        // Run by run, in reverse, so attributes stay attached even where uppercasing changes length (ß → SS)
        var runs: [(NSRange, String)] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { _, range, _ in
            runs.append((range, (text.string as NSString).substring(with: range).uppercased()))
        }
        runs.reversed().forEach { text.replaceCharacters(in: $0.0, with: $0.1) }
    }

    private func paragraphStyle(lineHeight: CGFloat, before: CGFloat = 0, after: CGFloat = 0,
                                head: CGFloat = 0, tail: CGFloat = 0, alignment: NSTextAlignment = .natural) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.firstLineHeadIndent = head
        style.headIndent = head
        style.tailIndent = tail
        style.alignment = alignment
        return style
    }

    /// First paragraph of a list item: the prefix hangs left of the content, aligned by a tab stop
    private func listItemStyle(contentIndent: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2   // list items sit closer together than body paragraphs
        style.paragraphSpacingBefore = 3
        style.paragraphSpacing = 3
        style.firstLineHeadIndent = contentIndent - Self.listStep + 4
        style.headIndent = contentIndent
        style.tabStops = [NSTextTab(textAlignment: .left, location: contentIndent)]
        style.defaultTabInterval = Self.listStep
        return style
    }
}
