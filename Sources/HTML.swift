import Foundation

enum HTML {
    /// Readable plain text from an article body. Line breaks follow block tags, not source newlines.
    static func plainText(_ html: String) -> String {
        var s = html.replacing(/\r?\n/, with: " ")
        s = s.replacing(/(?is)<(script|style|head)\b.*?<\/\1>/, with: "")
        s = s.replacing(/(?i)<\/(p|blockquote|pre|h[1-6])>/, with: "\n\n")
        s = s.replacing(/(?i)<br\s*\/?>|<\/(div|li|tr)>/, with: "\n")
        s = s.replacing(/<[^>]*>/, with: "")
        s = s.replacing(/&#(\d+);/) { m in UInt32(m.1).flatMap(Unicode.Scalar.init).map { String($0) } ?? "" }
        s = s.replacing(/&#[xX]([0-9a-fA-F]+);/) { m in UInt32(m.1, radix: 16).flatMap(Unicode.Scalar.init).map { String($0) } ?? "" }
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            s = s.replacing(entity, with: char)
        }
        s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacing(/[ \t]+/, with: " ").trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
        return s.replacing(/\n{3,}/, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
