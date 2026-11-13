import Foundation
import Testing
@testable import TicketMaster

@MainActor @Suite struct ZammadTests {
    @Test func serverURLRequiresHTTPS() throws {
        #expect(try ZammadClient.serverURL(" helpdesk.example.com/ ").absoluteString == "https://helpdesk.example.com")
        #expect(try ZammadClient.serverURL("https://h.example.com/zammad").absoluteString == "https://h.example.com/zammad")
        #expect(throws: ZammadError.self) { try ZammadClient.serverURL("http://helpdesk.example.com") }
        #expect(throws: ZammadError.self) { try ZammadClient.serverURL("") }
    }

    @Test func requestCarriesTokenAndSnakeCaseBody() throws {
        let client = ZammadClient(baseURL: URL(string: "https://h.example.com/zammad")!, token: "abc")
        let draft = ArticleDraft(ticketId: 5, body: "Hi", kind: .note, to: "x@example.com")
        let request = try client.makeRequest("POST", "ticket_articles", query: [.init(name: "expand", value: "true")], body: draft)
        #expect(request.url?.absoluteString == "https://h.example.com/zammad/api/v1/ticket_articles?expand=true")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Token token=abc")
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(json["ticket_id"] as? Int == 5)
        #expect(json["type"] as? String == "note")
        #expect(json["internal"] as? Bool == true)
        #expect(json["to"] == nil)
    }

    @Test func replyIsPublicEmailToCustomer() {
        let draft = ArticleDraft(ticketId: 1, body: "x", kind: .reply, to: "David <d@example.com>")
        #expect(draft.type == "email" && !draft.internal && draft.to == "David <d@example.com>")
    }

    @Test func filterQueries() {
        #expect(TicketFilter.all.query(search: "  ", meID: 3) == "*")
        #expect(TicketFilter.all.query(search: "order", meID: 3) == "order")
        #expect(TicketFilter.mine.query(search: "", meID: 3) == TicketFilter.openStates + " AND owner_id:3")
        #expect(TicketFilter.open.query(search: "order", meID: nil) == "(order) AND " + TicketFilter.openStates)
    }

    @Test func connectLoadsUserStatesAndTickets() async throws {
        let model = AppModel()
        try await model.connect(Demo.client)
        #expect(model.me?.displayName == "Emma Taylor")
        #expect(!model.states.contains { $0.name == "merged" })
        let tickets = try await Demo.client.searchTickets("*")
        #expect(tickets.map(\.number) == ["22001", "22002", "22003", "22004"])
        #expect(tickets[1].state == "open" && tickets[1].customer == "david@example.com")
        let articles = try await Demo.client.articles(ticket: 2)
        #expect(articles.count == 3 && articles[1].internal)
        #expect(articles[0].createdAt == ISO8601DateFormatter().date(from: "2026-11-12T11:57:18Z")!.addingTimeInterval(0.068))
    }

    @Test func wrongTokenGivesReadableError() async {
        let client = ZammadClient(baseURL: Demo.server, token: "wrong", session: FixtureProtocol.session)
        await #expect(throws: ZammadError(message: "The token was rejected. Check it under Profile > Token Access in Zammad.")) {
            try await client.me()
        }
    }

    @Test func htmlBecomesReadableText() throws {
        let article = try ZammadClient.decoder.decode([Article].self, from: Data(Demo.articles.utf8))[0]
        #expect(article.text.hasPrefix("Hi,\n\nplease send me:\n1 x Café Kopi susu\n4 x Viennese melange"))
        #expect(article.text.hasSuffix("75007 Paris\n\nDavid Bell"))
        #expect(HTML.plainText("<p>a &amp; b&nbsp;&lt;c&gt; &#228;&#x1F600;</p><style>x{}</style><p>d</p>") == "a & b <c> ä😀\n\nd")
    }
}
