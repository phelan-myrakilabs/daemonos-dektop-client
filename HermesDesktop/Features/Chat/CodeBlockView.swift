import AppKit
import SwiftUI

/// Fenced code block: mono 12pt on `codeBackground`, radius(8), horizontal
/// scroll, language label + copy button revealed on hover. Lightweight
/// regex-free keyword highlighting for a handful of languages; plain mono
/// for everything else.
struct CodeBlockView: View {
    let language: String
    let code: String

    @Environment(\.hermesTheme) private var theme
    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .overlay(theme.hairline)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(code, language: language, theme: theme))
                    .font(HermesTheme.monoFont(size: 12))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .background(theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: HermesTheme.radius(8)))
        .overlay(
            RoundedRectangle(cornerRadius: HermesTheme.radius(8))
                .strokeBorder(theme.strokeSecondary, lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Reference CodeCard label: "Code · <language>" (bare "Code" when unknown).
            Text(language.isEmpty ? "Code" : "Code · \(language)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 0)
            Button(action: copy) {
                Label(didCopy ? "Copied" : "Copy code",
                      systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Copy code")
            // Rests at 55% opacity, full on hover (reference copy affordance).
            .opacity(didCopy || isHovering ? 1 : 0.55)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopy = false
        }
    }
}

// MARK: - Highlighting

enum CodeHighlighter {
    /// Skip highlighting for very large blocks (streaming safety valve).
    static let maxHighlightChars = 20_000

    struct LanguageProfile {
        let keywords: Set<String>
        let lineComment: String?
        let blockComment: (open: String, close: String)?
        let stringDelimiters: Set<Character>
    }

    static func profile(for language: String) -> LanguageProfile? {
        switch language.lowercased() {
        case "swift":
            return LanguageProfile(
                keywords: ["actor", "as", "async", "await", "break", "case", "catch", "class",
                           "continue", "default", "defer", "deinit", "do", "else", "enum",
                           "extension", "fallthrough", "false", "final", "for", "func", "guard",
                           "if", "import", "in", "init", "inout", "internal", "is", "lazy", "let",
                           "nil", "nonisolated", "open", "override", "private", "protocol",
                           "public", "repeat", "rethrows", "return", "self", "Self", "some",
                           "static", "struct", "subscript", "super", "switch", "throw", "throws",
                           "true", "try", "typealias", "var", "weak", "where", "while"],
                lineComment: "//",
                blockComment: ("/*", "*/"),
                stringDelimiters: ["\""]
            )
        case "python", "py":
            return LanguageProfile(
                keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue",
                           "def", "del", "elif", "else", "except", "False", "finally", "for",
                           "from", "global", "if", "import", "in", "is", "lambda", "None",
                           "nonlocal", "not", "or", "pass", "raise", "return", "True", "try",
                           "while", "with", "yield", "self"],
                lineComment: "#",
                blockComment: nil,
                stringDelimiters: ["\"", "'"]
            )
        case "js", "javascript", "jsx", "ts", "typescript", "tsx":
            return LanguageProfile(
                keywords: ["abstract", "any", "as", "async", "await", "break", "case", "catch",
                           "class", "const", "continue", "default", "delete", "do", "else",
                           "enum", "export", "extends", "false", "finally", "for", "from",
                           "function", "if", "implements", "import", "in", "instanceof",
                           "interface", "let", "new", "null", "of", "return", "static", "super",
                           "switch", "this", "throw", "true", "try", "type", "typeof",
                           "undefined", "var", "void", "while", "yield"],
                lineComment: "//",
                blockComment: ("/*", "*/"),
                stringDelimiters: ["\"", "'", "`"]
            )
        case "json":
            return LanguageProfile(
                keywords: ["true", "false", "null"],
                lineComment: nil,
                blockComment: nil,
                stringDelimiters: ["\""]
            )
        case "bash", "sh", "shell", "zsh":
            return LanguageProfile(
                keywords: ["case", "do", "done", "elif", "else", "esac", "exit", "export", "fi",
                           "for", "function", "if", "in", "local", "return", "then", "until",
                           "while", "echo", "cd", "set"],
                lineComment: "#",
                blockComment: nil,
                stringDelimiters: ["\"", "'"]
            )
        default:
            return nil
        }
    }

    static func highlight(_ code: String, language: String, theme: HermesTheme) -> AttributedString {
        guard code.count <= maxHighlightChars, let profile = profile(for: language) else {
            return AttributedString(code)
        }

        var result = AttributedString()
        var inBlockComment = false
        let lines = code.components(separatedBy: "\n")

        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 { result += AttributedString("\n") }
            result += highlightLine(line,
                                    profile: profile,
                                    theme: theme,
                                    inBlockComment: &inBlockComment)
        }
        return result
    }

    private static func highlightLine(_ line: String,
                                      profile: LanguageProfile,
                                      theme: HermesTheme,
                                      inBlockComment: inout Bool) -> AttributedString {
        var out = AttributedString()
        let chars = Array(line)
        var index = 0

        func emit(_ text: String, _ color: Color?) {
            guard !text.isEmpty else { return }
            var run = AttributedString(text)
            if let color { run.foregroundColor = color }
            out += run
        }

        func matches(_ token: String, at position: Int) -> Bool {
            guard position + token.count <= chars.count else { return false }
            return String(chars[position..<(position + token.count)]) == token
        }

        while index < chars.count {
            if inBlockComment, let block = profile.blockComment {
                var comment = ""
                while index < chars.count {
                    if matches(block.close, at: index) {
                        comment += block.close
                        index += block.close.count
                        inBlockComment = false
                        break
                    }
                    comment.append(chars[index])
                    index += 1
                }
                emit(comment, theme.textTertiary)
                continue
            }

            let char = chars[index]

            if let block = profile.blockComment, matches(block.open, at: index) {
                inBlockComment = true
                continue
            }

            if let lineComment = profile.lineComment, matches(lineComment, at: index) {
                emit(String(chars[index...]), theme.textTertiary)
                break
            }

            if profile.stringDelimiters.contains(char) {
                var literal = String(char)
                index += 1
                while index < chars.count {
                    let current = chars[index]
                    literal.append(current)
                    index += 1
                    if current == "\\", index < chars.count {
                        literal.append(chars[index])
                        index += 1
                        continue
                    }
                    if current == char { break }
                }
                emit(literal, theme.statusSuccess)
                continue
            }

            if char.isNumber {
                var number = ""
                while index < chars.count,
                      chars[index].isNumber || chars[index] == "." || chars[index] == "_" {
                    number.append(chars[index])
                    index += 1
                }
                emit(number, theme.statusWarning)
                continue
            }

            if char.isLetter || char == "_" {
                var word = ""
                while index < chars.count,
                      chars[index].isLetter || chars[index].isNumber || chars[index] == "_" {
                    word.append(chars[index])
                    index += 1
                }
                emit(word, profile.keywords.contains(word) ? theme.accent : nil)
                continue
            }

            emit(String(char), nil)
            index += 1
        }
        return out
    }
}
