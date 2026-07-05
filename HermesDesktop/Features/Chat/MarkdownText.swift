import SwiftUI

/// Hand-rolled streaming-tolerant markdown renderer (no dependencies).
///
/// Fenced code blocks are split out first; the remaining text is grouped into
/// headings, lists, blockquotes, rules, and paragraphs. Inline runs (bold /
/// italic / inline code / links) go through `AttributedString(markdown:)` with
/// inline-only parsing — CommonMark leaves unterminated emphasis/backticks
/// literal, which is exactly the mid-stream tolerance we need. An unterminated
/// fence treats the rest of the text as code. The whole view is a pure function
/// of the input string and re-parses on each streaming flush.
struct MarkdownText: View {
    let text: String

    @Environment(\.hermesTheme) private var theme

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 11) { // --paragraph-gap ≈ 0.7rem
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let content):
            inlineText(content, size: 13)
                .lineSpacing(3)
        case .heading(let level, let content):
            inlineText(content, size: headingSize(level))
                .fontWeight(.semibold)
                .padding(.top, 4)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .bullet(let entries):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textSecondary)
                        inlineText(entry, size: 13)
                    }
                }
            }
        case .ordered(let entries):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(entry.number).")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                        inlineText(entry.text, size: 13)
                    }
                }
            }
        case .quote(let lines):
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(theme.strokePrimary)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        inlineText(line, size: 13)
                            .italic()
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(.leading, 12)
            }
        case .rule:
            // The reference renders `---` as an empty spacer, no visible line.
            Color.clear.frame(height: 6)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 16
        case 2: return 15
        case 3: return 14
        default: return 13
        }
    }

    private func inlineText(_ raw: String, size: CGFloat) -> Text {
        Text(MarkdownInline.render(raw, size: size, theme: theme))
            .font(.system(size: size))
            .foregroundStyle(theme.textPrimary)
    }
}

// MARK: - Inline rendering

enum MarkdownInline {
    /// Renders inline markdown (bold/italic/inline code/links) to an
    /// AttributedString, falling back to plain text on parse failure.
    static func render(_ raw: String, size: CGFloat, theme: HermesTheme) -> AttributedString {
        var attributed: AttributedString
        if let parsed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            attributed = parsed
        } else {
            attributed = AttributedString(raw)
        }

        // Collect styled ranges first, then apply (attribute-only mutations keep
        // ranges valid, but mutating while iterating runs is undefined).
        var codeRanges: [Range<AttributedString.Index>] = []
        var linkRanges: [Range<AttributedString.Index>] = []
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                codeRanges.append(run.range)
            }
            if run.link != nil {
                linkRanges.append(run.range)
            }
        }
        for range in codeRanges {
            attributed[range].font = HermesTheme.monoFont(size: size * 0.92)
            attributed[range].backgroundColor = theme.codeBackground
        }
        for range in linkRanges {
            attributed[range].foregroundColor = theme.accent
            attributed[range].underlineStyle = .single
        }
        return attributed
    }
}

// MARK: - Block parsing

enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(language: String, code: String)
    case bullet([String])
    case ordered([(number: Int, text: String)])
    case quote([String])
    case rule
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0

        var paragraph: [String] = []
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code — parsed first; an unterminated fence swallows the rest.
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                let code = codeLines.joined(separator: "\n")
                // Empty / still-open fences render nothing (no empty card flash).
                if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.code(language: language, code: code))
                }
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let heading = headingLine(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quoteLines))
                continue
            }

            if unorderedItem(trimmed) != nil {
                flushParagraph()
                var entries: [String] = []
                while index < lines.count,
                      let item = unorderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    entries.append(item)
                    index += 1
                }
                blocks.append(.bullet(entries))
                continue
            }

            if orderedItem(trimmed) != nil {
                flushParagraph()
                var entries: [(number: Int, text: String)] = []
                while index < lines.count,
                      let item = orderedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    entries.append(item)
                    index += 1
                }
                blocks.append(.ordered(entries))
                continue
            }

            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    private static func headingLine(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" })
        let level = hashes.count
        guard level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (number, String(rest.dropFirst(2)))
    }
}
