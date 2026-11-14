import Foundation

/// An article body split into what the author wrote and the earlier messages quoted below it.
struct BodyParts: Equatable {
    var main: String
    var quoted: String

    init(main: String, quoted: String = "") {
        self.main = main
        self.quoted = quoted
    }

    /// Splits at the first sign of quoted history. If nothing but quoted text would be left (a forwarded mail), keeps everything.
    init(body: String, isHTML: Bool) {
        var quoted = ""
        var text = body
        if isHTML {
            if let cut = body.firstMatch(of: Self.htmlQuote)?.range.lowerBound {
                text = String(body[..<cut])
                quoted = HTML.plainText(String(body[cut...]))
            }
            text = HTML.plainText(text)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let i = lines.indices.first(where: { Self.startsQuote(lines, at: $0) }) {
            let rest = lines[i...].joined(separator: "\n")
            quoted = quoted.isEmpty ? rest : rest + "\n\n" + quoted
            text = lines[..<i].joined(separator: "\n")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self = text.isEmpty ? BodyParts(main: isHTML ? HTML.plainText(body) : body) : BodyParts(main: text, quoted: quoted.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // Containers that Gmail, Outlook, Yahoo, Apple Mail and Thunderbird wrap around the quoted mail.
    private static let htmlQuote = /(?i)<blockquote\b|<[a-z]+\b[^>]*(?:class|id)="[^"]*(?:gmail_quote|gmail_attr|yahoo_quoted|divRplyFwdMsg|appendonsend|OLK_SRC_BODY_SECTION|moz-cite-prefix)/

    private static let separator = /(?i)^-{2,}\s*(?:original message|original-nachricht|ursprüngliche nachricht|weitergeleitete nachricht|forwarded message)/
    private static let attribution = /(?i)^(?:on|am)\s.{5,200}(?:wrote|schrieb).{0,100}:\s*$/
    private static let headerStart = /(?i)^(?:von|from):\s*\S/
    private static let headerField = /(?i)^(?:gesendet|sent|datum|date|an|to|betreff|subject):/

    private static func startsQuote(_ lines: [String], at i: Int) -> Bool {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        if line.hasPrefix(">") || line.firstMatch(of: separator) != nil { return true }
        // "On … wrote:" often wraps onto the next line.
        let next = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""
        if line.firstMatch(of: attribution) != nil || (!next.isEmpty && (line + " " + next).firstMatch(of: attribution) != nil) { return true }
        if line.firstMatch(of: headerStart) != nil {  // Outlook's "Von: … Gesendet: … An: … Betreff: …" block
            return lines.dropFirst(i + 1).prefix(4).contains { $0.trimmingCharacters(in: .whitespaces).firstMatch(of: headerField) != nil }
        }
        return false
    }
}

extension Article {
    var parts: BodyParts { BodyParts(body: body, isHTML: contentType == "text/html") }
}
