import AppKit

nonisolated struct SyntaxToken {
    let nsRange: NSRange
    let color: NSColor
}

nonisolated enum SyntaxHighlighter {

    static func tokenize(_ code: String, language: String?) -> [SyntaxToken] {
        guard let lang = language?.lowercased() else { return [] }
        switch lang {
        case "swift":                           return apply(swiftRegexes, to: code)
        case "python", "py":                    return apply(pythonRegexes, to: code)
        case "json":                            return apply(jsonRegexes, to: code)
        case "bash", "sh", "shell", "zsh":     return apply(bashRegexes, to: code)
        case "javascript", "js", "typescript", "ts": return apply(jsRegexes, to: code)
        case "css":                             return apply(cssRegexes, to: code)
        default:                                return []
        }
    }

    // MARK: - Adaptive colors

    private static let colorKeyword   = NSColor.systemPink
    private static let colorString    = NSColor.systemGreen
    private static let colorComment   = NSColor.secondaryLabelColor
    private static let colorNumber    = NSColor.systemOrange
    private static let colorType      = NSColor(name: nil) { app in
        app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1)
            : NSColor(red: 0.0,  green: 0.50, blue: 0.75, alpha: 1)
    }
    private static let colorAttr     = NSColor.systemYellow
    private static let colorJsonKey  = NSColor.systemBlue

    // MARK: - Compiled regex tables (built once)

    private static let swiftRegexes: [(NSRegularExpression, NSColor)] = compile([
        (#"\/\*[\s\S]*?\*\/"#,                                                          colorComment,  []),
        (#"\/\/.*$"#,                                                                   colorComment,  [.anchorsMatchLines]),
        (#"\"(?:[^\"\\]|\\.)*\""#,                                                      colorString,   []),
        (#"@\w+"#,                                                                      colorAttr,     []),
        (#"\b(func|var|let|class|struct|enum|protocol|extension|import|return|if|else|guard|switch|case|for|while|in|do|try|catch|throw|throws|async|await|actor|nonisolated|public|private|internal|fileprivate|open|override|final|static|lazy|weak|unowned|mutating|inout|where|associatedtype|typealias|some|any|Self|self|super|init|deinit|get|set|willSet|didSet|true|false|nil)\b"#, colorKeyword, []),
        (#"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#,                                       colorNumber,   []),
        (#"\b[A-Z][a-zA-Z0-9_]*\b"#,                                                   colorType,     []),
    ])

    private static let pythonRegexes: [(NSRegularExpression, NSColor)] = compile([
        (#"\"\"\"[\s\S]*?\"\"\"|\'\'\'[\s\S]*?\'\'\'"#,                                 colorString,   []),
        (#"\"(?:[^\"\\]|\\.)*\"|\'(?:[^\'\\]|\\.)*\'"#,                                 colorString,   []),
        (#"#.*$"#,                                                                      colorComment,  [.anchorsMatchLines]),
        (#"@[a-zA-Z_]\w*"#,                                                             colorAttr,     []),
        (#"\b(def|class|import|from|if|elif|else|return|pass|break|continue|for|while|try|except|finally|with|as|lambda|and|or|not|in|is|None|True|False|global|nonlocal|del|yield|assert|raise|async|await|self|cls)\b"#, colorKeyword, []),
        (#"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#,                                       colorNumber,   []),
        (#"\b[A-Z][a-zA-Z0-9_]*\b"#,                                                   colorType,     []),
    ])

    private static let jsonRegexes: [(NSRegularExpression, NSColor)] = compile([
        (#"\"(?:[^\"\\]|\\.)*\"(?=\s*:)"#,                                              colorJsonKey,  []),
        (#"\"(?:[^\"\\]|\\.)*\""#,                                                      colorString,   []),
        (#"\b(true|false|null)\b"#,                                                     colorKeyword,  []),
        (#"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#,                            colorNumber,   []),
    ])

    private static let bashRegexes: [(NSRegularExpression, NSColor)] = compile([
        (#"#.*$"#,                                                                      colorComment,  [.anchorsMatchLines]),
        (#"\"(?:[^\"\\]|\\.)*\"|\'[^\']*\'"#,                                           colorString,   []),
        (#"\$\{?[a-zA-Z_]\w*\}?"#,                                                     colorAttr,     []),
        (#"\b(if|then|else|elif|fi|while|do|done|for|in|case|esac|function|return|echo|export|source|local|readonly|shift|set|unset|trap|exit|cd|mkdir|rm|cp|mv|ls|cat|grep|awk|sed|curl|git)\b"#, colorKeyword, []),
        (#"(?:^|\s)(-{1,2}[a-zA-Z][a-zA-Z0-9-]*)"#,                                   colorType,     [.anchorsMatchLines]),
        (#"\b\d+\b"#,                                                                   colorNumber,   []),
    ])

    private static let jsRegexes: [(NSRegularExpression, NSColor)] = compile([
        (#"\/\*[\s\S]*?\*\/"#,                                                          colorComment,  []),
        (#"\/\/.*$"#,                                                                   colorComment,  [.anchorsMatchLines]),
        (#"`(?:[^`\\]|\\.)*`|\"(?:[^\"\\]|\\.)*\"|\'(?:[^\'\\]|\\.)*\'"#,              colorString,   []),
        (#"\b(function|const|let|var|class|extends|return|if|else|for|while|do|switch|case|break|continue|import|export|default|from|async|await|try|catch|finally|throw|new|this|super|typeof|instanceof|in|of|true|false|null|undefined|void)\b"#, colorKeyword, []),
        (#"\b\d+(?:\.\d+)?\b"#,                                                        colorNumber,   []),
        (#"\b[A-Z][a-zA-Z0-9_]*\b"#,                                                   colorType,     []),
    ])

    private static let cssRegexes: [(NSRegularExpression, NSColor)] = compile([
        (#"\/\*[\s\S]*?\*\/"#,                                                          colorComment,  []),
        (#"\"(?:[^\"\\]|\\.)*\"|\'(?:[^\'\\]|\\.)*\'"#,                                 colorString,   []),
        (#"#[0-9a-fA-F]{3,8}\b"#,                                                      colorAttr,     []),
        (#"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:%|px|em|rem|vh|vw|pt|s|ms)?\b"#,              colorNumber,   []),
        (#"[.#]?[a-zA-Z][a-zA-Z0-9_-]*(?=\s*\{)"#,                                    colorType,     []),
        (#"[a-zA-Z-]+(?=\s*:)"#,                                                       colorJsonKey,  []),
    ])

    // MARK: - Engine

    private static func apply(_ regexes: [(NSRegularExpression, NSColor)], to code: String) -> [SyntaxToken] {
        var used: [NSRange] = []
        var tokens: [SyntaxToken] = []
        let fullRange = NSRange(code.startIndex..., in: code)

        for (regex, color) in regexes {
            regex.enumerateMatches(in: code, range: fullRange) { match, _, _ in
                guard let match else { return }
                // Use capture group 1 if present (e.g. bash flags), else full match
                let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1)
                    : match.range
                guard range.location != NSNotFound, !overlaps(range, used) else { return }
                used.append(range)
                tokens.append(SyntaxToken(nsRange: range, color: color))
            }
        }
        return tokens
    }

    private static func overlaps(_ range: NSRange, _ existing: [NSRange]) -> Bool {
        existing.contains { r in range.lowerBound < r.upperBound && range.upperBound > r.lowerBound }
    }

    private static func compile(_ defs: [(String, NSColor, NSRegularExpression.Options)]) -> [(NSRegularExpression, NSColor)] {
        defs.compactMap { (pattern, color, opts) in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
            return (regex, color)
        }
    }
}
