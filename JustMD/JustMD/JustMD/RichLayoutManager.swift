import AppKit

// Custom attribute keys we add in post-processing (readable in our layout manager)
extension NSAttributedString.Key {
    // nonisolated: read by the background renderer and by drawing callbacks
    nonisolated static let codeBackground     = NSAttributedString.Key("richCodeBackground")
    nonisolated static let quoteStripeColor   = NSAttributedString.Key("richQuoteStripeColor")
    nonisolated static let thematicBreakColor = NSAttributedString.Key("richThematicBreakColor")
    nonisolated static let quoteBackground    = NSAttributedString.Key("richQuoteBackground")
}

struct CodeBlockInfo {
    let range: NSRange
    let language: String?
}

/// Custom NSLayoutManager that draws code block backgrounds, quote stripes,
/// thematic breaks, heading underlines, and language labels.
///
/// nonisolated(unsafe) properties are safe here: written only from @MainActor
/// (updateNSView) and read only from drawing callbacks which run on the main thread.
final class RichLayoutManager: NSLayoutManager {

    nonisolated(unsafe) var codeBlocks: [CodeBlockInfo] = []
    nonisolated(unsafe) var headingRanges: [(range: NSRange, level: Int)] = []
    nonisolated(unsafe) var listPrefixRanges: [(range: NSRange, nested: Bool)] = []
    nonisolated(unsafe) var checkboxRanges: [(range: NSRange, isDone: Bool)] = []
    nonisolated(unsafe) var tableRanges: [NSRange] = []

    override init() { super.init() }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: - Background: code block rounded rects

    nonisolated override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawRuledLines(for: glyphsToShow, at: origin)
        drawCodeBackgrounds(for: glyphsToShow, at: origin)
        drawCodeBlockChrome(for: glyphsToShow, at: origin)
        drawQuoteBackgrounds(for: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        drawTableBorders(for: glyphsToShow, at: origin)
    }

    /// Decorations are drawn per visible tile; querying layout for off-screen blocks would force
    /// TextKit to lay out the whole document and defeat non-contiguous layout.
    nonisolated private func visibleCodeBlocks(in glyphRange: NSRange) -> [CodeBlockInfo] {
        let chars = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        return codeBlocks.filter { NSIntersectionRange(chars, $0.range).length > 0 }
    }

    /// One soft panel per blockquote, behind its stripe. Uses the quote's whole run (not just the
    /// visible tile) so the rounded corners land once, at the quote's real ends.
    nonisolated private func drawQuoteBackgrounds(for glyphRange: NSRange, at origin: CGPoint) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        let key = NSAttributedString.Key("richQuoteBackground")
        let visible = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var drawn = Set<Int>()
        storage.enumerateAttribute(key, in: visible) { value, range, _ in
            guard let color = value as? NSColor else { return }
            var quote = NSRange()
            _ = storage.attribute(key, at: range.location, longestEffectiveRange: &quote,
                                  in: NSRange(location: 0, length: storage.length))
            guard drawn.insert(quote.location).inserted else { return }
            var union: CGRect?
            enumerateLineFragments(forGlyphRange: self.glyphRange(forCharacterRange: quote, actualCharacterRange: nil)) { lineRect, usedRect, _, _, _ in
                guard usedRect.height > 0 else { return }
                union = union.map { $0.union(lineRect) } ?? lineRect
            }
            guard let rect = union else { return }
            let pad = container.lineFragmentPadding
            let panel = CGRect(x: origin.x + pad, y: rect.minY + origin.y,
                               width: container.size.width - 2 * pad, height: rect.height)
            guard panel.width > 0, panel.height > 0 else { return }
            color.setFill()
            NSBezierPath(roundedRect: panel, xRadius: 6, yRadius: 6).fill()
        }
    }

    nonisolated private func drawRuledLines(for glyphRange: NSRange, at origin: CGPoint) {
        // Only in light mode
        guard !Theme.isDark() else { return }
        guard let tc = textContainers.first else { return }

        let containerRect = tc.size
        guard containerRect.width.isFinite, containerRect.width > 0 else { return }

        // Compute the y-range to draw within
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = CGFloat.zero
        enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            minY = Swift.min(minY, usedRect.minY)
            maxY = Swift.max(maxY, usedRect.maxY)
        }
        guard minY < maxY else { return }

        // Build set of code block y-ranges to skip
        var codeYRanges: [(CGFloat, CGFloat)] = []
        for block in visibleCodeBlocks(in: glyphRange) {
            let blockGlyphRange = self.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            var blockMin = CGFloat.greatestFiniteMagnitude
            var blockMax = CGFloat.zero
            enumerateLineFragments(forGlyphRange: blockGlyphRange) { lineRect, _, _, _, _ in
                blockMin = Swift.min(blockMin, lineRect.minY)
                blockMax = Swift.max(blockMax, lineRect.maxY)
            }
            if blockMin < blockMax { codeYRanges.append((blockMin - 3, blockMax + 3)) }
        }

        NSColor(white: 0, alpha: 0.025).setFill()
        let lineSpacing: CGFloat = 28
        var y = (floor(minY / lineSpacing) * lineSpacing)
        while y <= maxY {
            let inCode = codeYRanges.contains { y >= $0.0 && y <= $0.1 }
            if !inCode {
                let lineRect = CGRect(
                    x: origin.x,
                    y: y + origin.y,
                    width: containerRect.width,
                    height: 1
                )
                NSBezierPath(rect: lineRect).fill()
            }
            y += lineSpacing
        }
    }

    nonisolated private func drawCodeBlockChrome(for glyphsToShow: NSRange, at origin: CGPoint) {
        for block in visibleCodeBlocks(in: glyphsToShow) {
            let blockGlyphRange = glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            guard blockGlyphRange.length > 0,
                  blockGlyphRange.location < numberOfGlyphs else { continue }
            guard NSIntersectionRange(glyphsToShow, blockGlyphRange).length > 0 else { continue }

            // Compute the full block rect (union of all line fragments)
            var blockRect: CGRect? = nil
            enumerateLineFragments(forGlyphRange: blockGlyphRange) { lineRect, usedRect, _, _, _ in
                guard usedRect.height > 0 else { return }  // skip phantom infinite-height line fragment
                blockRect = blockRect.map { $0.union(lineRect) } ?? lineRect
            }
            guard var rect = blockRect else { continue }
            rect = rect.insetBy(dx: 0, dy: -3).offsetBy(dx: origin.x, dy: origin.y)
            guard rect.width > 0, rect.height > 0 else { continue }  // degenerate → NaN gradient

            // ── 2px gradient top bar ──
            let barRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2)
            if let gradient = NSGradient(
                colors: [Theme.accentPrimary, Theme.accentSecondary],
                atLocations: [0.0, 1.0],
                colorSpace: .genericRGB
            ) {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: barRect).setClip()
                gradient.draw(in: barRect, angle: 0)
                NSGraphicsContext.restoreGraphicsState()
            }

            // ── Header row background ──
            let firstLineRect = lineFragmentRect(forGlyphAt: blockGlyphRange.location, effectiveRange: nil)
                .offsetBy(dx: origin.x, dy: origin.y)
            // Start header at rect.minY + 2 (just below the 2px top bar) to fill the inset gap
            let headerRect = CGRect(x: rect.minX, y: rect.minY + 2,
                                    width: rect.width, height: firstLineRect.height + 3)
            Theme.bgCodeHeader.setFill()
            NSBezierPath(rect: headerRect).fill()

            // ── Traffic light dots (only if block wide enough to fit all three) ──
            if rect.width >= 60 {
                let dotY = firstLineRect.midY
                let dots: [(CGFloat, NSColor)] = [
                    (rect.minX + 14, Theme.trafficRed),
                    (rect.minX + 29, Theme.trafficAmber),
                    (rect.minX + 44, Theme.trafficGreen),
                ]
                for (x, color) in dots {
                    let dotRect = CGRect(x: x - 5.5, y: dotY - 5.5, width: 11, height: 11)
                    color.setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                }
            }
        }
    }

    nonisolated private func drawCodeBackgrounds(for glyphRange: NSRange, at origin: CGPoint) {
        guard let storage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        storage.enumerateAttribute(NSAttributedString.Key("richCodeBackground"), in: charRange) { value, blockCharRange, _ in
            guard let color = value as? NSColor else { return }

            let blockGlyphRange = self.glyphRange(forCharacterRange: blockCharRange, actualCharacterRange: nil)
            var union: CGRect? = nil
            self.enumerateLineFragments(forGlyphRange: blockGlyphRange) { lineRect, usedRect, _, _, _ in
                guard usedRect.height > 0 else { return }  // skip phantom infinite-height line fragment
                union = union.map { $0.union(lineRect) } ?? lineRect
            }
            guard let rect = union else { return }

            let padded = rect.insetBy(dx: 0, dy: -3).offsetBy(dx: origin.x, dy: origin.y)
            color.setFill()
            NSBezierPath(roundedRect: padded, xRadius: 6, yRadius: 6).fill()
        }
    }

    // MARK: - Glyphs: quote stripes, thematic breaks, heading rules, language labels

    nonisolated override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        drawH1GradientText(charRange: charRange, at: origin)   // overdraw H1 glyphs with gradient
        drawH2Stripes(charRange: charRange, at: origin)
        drawQuoteStripes(storage: storage, charRange: charRange, at: origin)
        drawThematicBreaks(storage: storage, charRange: charRange, at: origin)
        drawHeadingRules(charRange: charRange, at: origin)
        drawBulletDots(charRange: charRange, at: origin)
        drawCheckboxes(charRange: charRange, at: origin)
        drawLanguageLabels(charRange: charRange, at: origin)
    }

    nonisolated private func drawH1GradientText(charRange: NSRange, at origin: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        for (headingRange, level) in headingRanges {
            guard level == 1 else { continue }
            guard NSIntersectionRange(charRange, headingRange).length > 0 else { continue }

            let gRange = glyphRange(forCharacterRange: headingRange, actualCharacterRange: nil)
            guard gRange.length > 0 else { continue }

            var boundingRect: CGRect? = nil
            enumerateLineFragments(forGlyphRange: gRange) { _, usedRect, _, _, _ in
                guard usedRect.width > 0, usedRect.height > 0 else { return }  // skip phantom/empty
                boundingRect = boundingRect.map { $0.union(usedRect) } ?? usedRect
            }
            guard var rect = boundingRect else { continue }
            rect = rect.offsetBy(dx: origin.x, dy: origin.y)
            guard rect.width > 0, rect.height > 0 else { continue }  // degenerate rect → NaN gradient

            let colors = Theme.h1GradientColors()
            let cgColors = colors.map { ($0.usingColorSpace(.deviceRGB) ?? $0).cgColor } as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: cgColors,
                locations: locations
            ) else { continue }

            let glyphOutlines = glyphPath(for: gRange, at: origin)
            guard !glyphOutlines.isEmpty else { continue }

            ctx.saveGState()
            ctx.addPath(glyphOutlines)
            ctx.clip()
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.minX, y: rect.midY),
                end:   CGPoint(x: rect.maxX, y: rect.midY),
                options: []
            )
            ctx.restoreGState()
        }
    }

    /// Union of glyph outlines in view coordinates, so a gradient can be clipped to the letterforms.
    nonisolated private func glyphPath(for gRange: NSRange, at origin: CGPoint) -> CGPath {
        let path = CGMutablePath()
        guard let storage = textStorage else { return path }
        for g in gRange.lowerBound..<min(gRange.upperBound, numberOfGlyphs) {
            guard propertyForGlyph(at: g).isDisjoint(with: [.controlCharacter, .null]),
                  let font = storage.attribute(.font, at: characterIndexForGlyph(at: g), effectiveRange: nil) as? NSFont,
                  let outline = CTFontCreatePathForGlyph(font, cgGlyph(at: g), nil) else { continue }
            let line = lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let loc = location(forGlyphAt: g)
            // Glyph outlines are y-up; the text view is flipped, so mirror around the baseline.
            let transform = CGAffineTransform(translationX: origin.x + line.minX + loc.x,
                                              y: origin.y + line.minY + loc.y).scaledBy(x: 1, y: -1)
            path.addPath(outline, transform: transform)
        }
        return path
    }

    nonisolated private func drawQuoteStripes(storage: NSTextStorage, charRange: NSRange, at origin: CGPoint) {
        storage.enumerateAttribute(NSAttributedString.Key("richQuoteStripeColor"), in: charRange) { value, quoteCharRange, _ in
            guard let color = value as? NSColor else { return }
            let gRange = self.glyphRange(forCharacterRange: quoteCharRange, actualCharacterRange: nil)
            self.enumerateLineFragments(forGlyphRange: gRange) { lineRect, usedRect, container, _, _ in
                guard usedRect.height > 0, lineRect.height.isFinite, lineRect.height > 0 else { return }
                let x = lineRect.minX + container.lineFragmentPadding + origin.x
                let stripeRect = CGRect(x: x, y: lineRect.minY + origin.y, width: 3, height: lineRect.height)
                color.setFill()
                NSBezierPath(rect: stripeRect).fill()
            }
        }
    }

    nonisolated private func drawThematicBreaks(storage: NSTextStorage, charRange: NSRange, at origin: CGPoint) {
        storage.enumerateAttribute(NSAttributedString.Key("richThematicBreakColor"), in: charRange) { value, range, _ in
            guard value != nil else { return }
            let gRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard gRange.length > 0, gRange.location < self.numberOfGlyphs else { return }
            let lineRect = self.lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: nil)
            let startX = lineRect.minX + origin.x
            let endX   = lineRect.maxX + origin.x
            guard endX > startX else { return }  // zero-width rect → NaN gradient

            let y = lineRect.midY + origin.y
            let mid = Theme.textMuted.withAlphaComponent(0.5)
            guard let gradient = NSGradient(
                colors: [.clear, mid, .clear],
                atLocations: [0.0, 0.5, 1.0],
                colorSpace: .genericRGB
            ) else { return }

            NSGraphicsContext.saveGraphicsState()
            let hrRect = CGRect(x: startX, y: y, width: endX - startX, height: 1)
            NSBezierPath(rect: hrRect).setClip()
            gradient.draw(in: hrRect, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    nonisolated private func drawHeadingRules(charRange: NSRange, at origin: CGPoint) {
        for (headingRange, level) in headingRanges {
            guard level == 1 else { continue }
            guard charRange.lowerBound < headingRange.upperBound,
                  charRange.upperBound > headingRange.lowerBound else { continue }
            let gRange = glyphRange(forCharacterRange: headingRange, actualCharacterRange: nil)
            guard gRange.length > 0 else { continue }
            let lastGlyph = gRange.upperBound - 1
            guard lastGlyph < numberOfGlyphs else { continue }
            let lineRect = lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let startX = lineRect.minX + origin.x
            let endX   = lineRect.maxX + origin.x
            guard endX > startX else { continue }  // zero-width → NaN gradient

            let y = (lineRect.maxY + origin.y).rounded() + 3
            let ruleColors = Theme.h1RuleColors()
            guard let gradient = NSGradient(
                colors: ruleColors,
                atLocations: [0.0, 0.5, 1.0],
                colorSpace: .genericRGB
            ) else { continue }

            let ruleRect = CGRect(x: startX, y: y, width: endX - startX, height: 2)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: ruleRect).setClip()
            gradient.draw(in: ruleRect, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    nonisolated private func drawH2Stripes(charRange: NSRange, at origin: CGPoint) {
        for (headingRange, level) in headingRanges {
            guard level == 2 else { continue }
            guard charRange.lowerBound < headingRange.upperBound,
                  charRange.upperBound > headingRange.lowerBound else { continue }
            let gRange = glyphRange(forCharacterRange: headingRange, actualCharacterRange: nil)
            guard gRange.length > 0, gRange.location < numberOfGlyphs else { continue }
            let lineRect = lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: nil)
            // lineRect includes paragraphSpacingBefore, so centre on the glyphs' cap height instead
            guard let font = textStorage?.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
            else { continue }
            let baseline = lineRect.minY + location(forGlyphAt: gRange.location).y + origin.y
            let stripeH = font.capHeight + 8
            guard stripeH > 0 else { continue }  // zero-height → NaN in rounded rect / gradient

            let stripeX = max(0, lineRect.minX + origin.x - 12)  // hangs into the left inset
            let stripeRect = CGRect(x: stripeX, y: baseline - font.capHeight - 4, width: 3, height: stripeH)

            guard let gradient = NSGradient(
                colors: [Theme.accentPrimary, Theme.accentSecondary],
                atLocations: [0.0, 1.0],
                colorSpace: .genericRGB
            ) else { continue }

            NSGraphicsContext.saveGraphicsState()
            let path = NSBezierPath(roundedRect: stripeRect, xRadius: 1.5, yRadius: 1.5)
            path.setClip()
            gradient.draw(in: stripeRect, angle: 270)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    nonisolated private func drawBulletDots(charRange: NSRange, at origin: CGPoint) {
        for (prefixRange, nested) in listPrefixRanges {
            guard NSIntersectionRange(charRange, prefixRange).length > 0 else { continue }
            let gRange = glyphRange(forCharacterRange: prefixRange, actualCharacterRange: nil)
            guard gRange.length > 0, gRange.location < numberOfGlyphs else { continue }
            let lineRect = lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: nil)
            let glyphOrigin = location(forGlyphAt: gRange.location)

            // Centre on the x-height so the dot lines up with lowercase text, not the padded line rect
            let xHeight = (textStorage?.attribute(.font, at: prefixRange.location, effectiveRange: nil) as? NSFont)?.xHeight ?? 7
            let cx = glyphOrigin.x + origin.x + lineRect.minX
            let cy = lineRect.minY + glyphOrigin.y + origin.y - xHeight / 2

            if nested {
                // Outlined ring — 6px diameter, 2px border
                let r: CGFloat = 3
                let dotRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                Theme.accentSecondary.setStroke()
                let path = NSBezierPath(ovalIn: dotRect)
                path.lineWidth = 2
                path.stroke()
            } else {
                // Filled dot — 7px diameter
                let r: CGFloat = 3.5
                let dotRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                Theme.accentPrimary.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }

    nonisolated private func drawCheckboxes(charRange: NSRange, at origin: CGPoint) {
        for (cbRange, isDone) in checkboxRanges {
            guard NSIntersectionRange(charRange, cbRange).length > 0 else { continue }
            let gRange = glyphRange(forCharacterRange: cbRange, actualCharacterRange: nil)
            guard gRange.length > 0, gRange.location < numberOfGlyphs else { continue }
            let lineRect = lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: nil)
            let glyphLoc = location(forGlyphAt: gRange.location)
            let x = glyphLoc.x + origin.x + lineRect.minX
            let xHeight = (textStorage?.attribute(.font, at: cbRange.location, effectiveRange: nil) as? NSFont)?.xHeight ?? 7
            let y = lineRect.minY + glyphLoc.y + origin.y - xHeight / 2 - 7.5

            let boxRect = CGRect(x: x, y: y, width: 15, height: 15)
            let path = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)

            if isDone {
                Theme.accentPrimary.setFill()
                path.fill()
                // Draw checkmark: two connected line segments
                let check = NSBezierPath()
                check.lineWidth = 2
                check.lineCapStyle = .round
                // Flipped view (y grows downward): the tick's low point has the largest y
                check.move(to: CGPoint(x: x + 3.5, y: y + 7.5))
                check.line(to: CGPoint(x: x + 6.5, y: y + 10.5))
                check.line(to: CGPoint(x: x + 11.5, y: y + 4.5))
                Theme.bgCodeBlock.setStroke()
                check.stroke()
            } else {
                Theme.bgPage.setFill()
                path.fill()
                Theme.textMuted.withAlphaComponent(0.5).setStroke()
                path.lineWidth = 2
                path.stroke()
            }
        }
    }

    nonisolated private func drawLanguageLabels(charRange: NSRange, at origin: CGPoint) {
        for block in codeBlocks {
            guard let lang = block.language, !lang.isEmpty else { continue }
            guard charRange.lowerBound < block.range.upperBound,
                  charRange.upperBound > block.range.lowerBound else { continue }
            let gRange = glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            guard gRange.location < numberOfGlyphs else { continue }
            let lineRect = lineFragmentRect(forGlyphAt: gRange.location, effectiveRange: nil)
            let container = textContainer(forGlyphAt: gRange.location, effectiveRange: nil)
            let padding = container?.lineFragmentPadding ?? 0
            let containerWidth = container?.size.width ?? lineRect.width
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: Theme.codeLabel
            ]
            let label = lang as NSString
            let size = label.size(withAttributes: attrs)
            let drawX = padding + containerWidth - size.width - 12 + origin.x
            let drawY = lineRect.minY + (lineRect.height - size.height) / 2 + origin.y
            label.draw(at: CGPoint(x: drawX, y: drawY), withAttributes: attrs)
        }
    }

    // MARK: - Table borders

    nonisolated private func drawTableBorders(for glyphRange: NSRange, at origin: CGPoint) {
        guard let storage = textStorage else { return }
        let visibleChars = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        for tableRange in tableRanges where NSIntersectionRange(visibleChars, tableRange).length > 0 {
            let blockGlyphRange = self.glyphRange(forCharacterRange: tableRange, actualCharacterRange: nil)
            guard blockGlyphRange.length > 0, blockGlyphRange.location < numberOfGlyphs else { continue }

            // Compute table rect: X/width come from container geometry (avoids line-fragment width ambiguity),
            // Y/height come from the actual line fragments in the table glyph range.
            guard let tc = textContainers.first else { continue }
            var minY: CGFloat = .greatestFiniteMagnitude
            var maxY: CGFloat = -.greatestFiniteMagnitude
            enumerateLineFragments(forGlyphRange: blockGlyphRange) { lineRect, usedRect, _, _, _ in
                // Skip phantom "extra line fragment" TextKit appends — it spans to container bottom
                // (height ≈ greatestFiniteMagnitude). usedRect.height == 0 for empty/phantom lines.
                guard usedRect.height > 0 else { return }
                minY = min(minY, lineRect.minY)
                maxY = max(maxY, lineRect.maxY)
            }
            guard minY < maxY else { continue }
            let pad = tc.lineFragmentPadding
            let tableX = pad + origin.x
            let tableW = tc.containerSize.width - 2 * pad
            guard tableW > 0, tableW.isFinite else { continue }  // skip if container unsized or infinite
            let rect = CGRect(x: tableX, y: minY + origin.y, width: tableW, height: maxY - minY)

            // Find max Y per NSTextTable row by reading NSTextTableBlock.startingRow.
            // This avoids drawing separators inside multi-line cells.
            var rowMaxY: [Int: CGFloat] = [:]
            storage.enumerateAttribute(.paragraphStyle, in: tableRange, options: []) { value, paraRange, _ in
                guard let ps = value as? NSParagraphStyle,
                      let block = ps.textBlocks.first as? NSTextTableBlock else { return }
                let rowIdx = block.startingRow
                let paraGlyphRange = self.glyphRange(forCharacterRange: paraRange, actualCharacterRange: nil)
                guard paraGlyphRange.length > 0, paraGlyphRange.location < self.numberOfGlyphs else { return }
                self.enumerateLineFragments(forGlyphRange: paraGlyphRange) { lineRect, _, _, _, _ in
                    rowMaxY[rowIdx] = max(rowMaxY[rowIdx] ?? 0, lineRect.maxY)
                }
            }

            NSGraphicsContext.saveGraphicsState()

            // Outer rounded border (radius 10px, textMuted@30%)
            Theme.textMuted.withAlphaComponent(0.3).setStroke()
            let outerPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
            outerPath.lineWidth = 1
            outerPath.stroke()

            // Row separator lines — one per row boundary, not per line fragment
            Theme.textMuted.withAlphaComponent(0.2).setStroke()
            let sortedRowIndices = rowMaxY.keys.sorted()
            for rowIdx in sortedRowIndices.dropLast() {
                guard let maxY = rowMaxY[rowIdx] else { continue }
                let y = maxY + origin.y
                guard y > rect.minY + 2 && y < rect.maxY - 2 else { continue }
                let sep = NSBezierPath()
                sep.move(to: CGPoint(x: rect.minX + 1, y: y))
                sep.line(to: CGPoint(x: rect.maxX - 1, y: y))
                sep.lineWidth = 1
                sep.stroke()
            }

            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
