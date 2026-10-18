import Foundation

/// Finds bare URLs (the parser has no autolink extension) and resolved footnote markers in text runs.
nonisolated enum InlineScanner {
    enum Kind: Equatable {
        case url(URL)
        case footnote(String)
    }

    struct Match: Equatable {
        let range: NSRange
        let kind: Kind
    }

    /// Footnote references are rewritten to U+E000 n U+E001 before parsing (see `PreviewRenderer.resolveFootnotes`)
    static let footnoteOpen = "\u{E000}", footnoteClose = "\u{E001}"

    private static let urlRegex = try! NSRegularExpression(pattern: #"(?i)\b(?:https?://|www\.)[^\s<>"\x{E000}]+"#)
    private static let footnoteRegex = try! NSRegularExpression(pattern: "\u{E000}(\\d+)\u{E001}")
    private static let trailingPunctuation = Set(".,;:!?'*_")

    static func matches(in text: String) -> [Match] {
        (urlMatches(in: text) + footnoteMatches(in: text)).sorted { $0.range.location < $1.range.location }
    }

    static func footnoteMatches(in text: String) -> [Match] {
        let ns = text as NSString
        return footnoteRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            Match(range: $0.range, kind: .footnote(ns.substring(with: $0.range(at: 1))))
        }
    }

    private static func urlMatches(in text: String) -> [Match] {
        guard text.contains("://") || text.localizedCaseInsensitiveContains("www.") else { return [] }
        let ns = text as NSString
        return urlRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            var candidate = ns.substring(with: match.range)
            // Sentence punctuation and an unmatched ")" belong to the prose, not the URL
            while let last = candidate.last,
                  trailingPunctuation.contains(last)
                    || (last == ")" && candidate.filter { $0 == "(" }.count < candidate.filter { $0 == ")" }.count) {
                candidate.removeLast()
            }
            let spelled = candidate.lowercased().hasPrefix("www.") ? "https://" + candidate : candidate
            guard let url = URL(string: spelled), url.host != nil else { return nil }
            return Match(range: NSRange(location: match.range.location, length: (candidate as NSString).length), kind: .url(url))
        }
    }
}

/// The small slice of HTML that shows up in real-world Markdown: formatting tags, line breaks,
/// images and centred blocks. Anything else is reduced to its text — never rendered as markup.
nonisolated enum HTMLText {
    enum InlineTag {
        case lineBreak
        case image(source: String, alt: String)
        case toggle((inout MarkdownBuilder.InlineStyle) -> Void)
    }

    private static let tagRegex = try! NSRegularExpression(pattern: #"^<\s*(/)?\s*([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>$"#)
    private static let imgRegex = try! NSRegularExpression(pattern: #"(?i)<img\b[^>]*>"#)
    private static let srcRegex = try! NSRegularExpression(pattern: #"(?i)\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
    private static let altRegex = try! NSRegularExpression(pattern: #"(?i)\balt\s*=\s*(?:"([^"]*)"|'([^']*)')"#)
    private static let anyTagRegex = try! NSRegularExpression(pattern: #"(?s)<!--.*?-->|<[^>]+>"#)
    private static let whitespaceRegex = try! NSRegularExpression(pattern: #"[ \t\r\n]+"#)

    static func inlineTag(_ raw: String) -> InlineTag? {
        let ns = raw as NSString
        guard let match = tagRegex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let opening = match.range(at: 1).location == NSNotFound
        switch ns.substring(with: match.range(at: 2)).lowercased() {
        case "br":                     return .lineBreak
        case "img":                    return images(in: raw).first.map { .image(source: $0.source, alt: $0.alt) }
        case "b", "strong":            return .toggle { $0.bold = opening }
        case "i", "em":                return .toggle { $0.italic = opening }
        case "s", "del", "strike":     return .toggle { $0.strike = opening }
        case "code", "kbd", "samp", "tt": return .toggle { $0.code = opening }
        case "sup":                    return .toggle { $0.superscript = opening }
        case "sub":                    return .toggle { $0.subscript_ = opening }
        case "u", "ins":               return .toggle { $0.underline = opening }
        case "mark":                   return .toggle { $0.highlight = opening }
        default:                       return nil
        }
    }

    static func images(in html: String) -> [(source: String, alt: String)] {
        let ns = html as NSString
        return imgRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let tag = ns.substring(with: match.range)
            guard let source = firstGroup(srcRegex, in: tag), !source.isEmpty else { return nil }
            return (source, firstGroup(altRegex, in: tag) ?? "")
        }
    }

    static func strip(_ html: String) -> String {
        let ns = html as NSString
        let noTags = anyTagRegex.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        let decoded = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
            .reduce(noTags) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        let collapsed = whitespaceRegex.stringByReplacingMatches(
            in: decoded, range: NSRange(location: 0, length: (decoded as NSString).length), withTemplate: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    static func isCentered(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("align=\"center\"") || lower.contains("align='center'")
            || lower.contains("align=center") || lower.contains("<center")
    }

    private static func firstGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<match.numberOfRanges).lazy
            .map { match.range(at: $0) }
            .first { $0.location != NSNotFound }
            .map { ns.substring(with: $0) }
    }
}
