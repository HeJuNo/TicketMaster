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
        let client = ZammadClient(baseURL: URL(string: "https://h.example.com/zammad")!, credential: .token("abc"))
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

    @Test func expiredSessionReports401() async {
        let client = ZammadClient(baseURL: Demo.server, credential: .session(WebSession()), urlSession: FixtureProtocol.session)
        await #expect(throws: ZammadError(message: "You have been signed out. Please sign in again.", status: 401)) {
            try await client.me()
        }
    }

    func demoModel() -> AppModel {
        let model = AppModel()
        model.urlSession = FixtureProtocol.session
        return model
    }

    @Test func passwordSignInUsesCookieAndCSRFLikeTheWebApp() async throws {
        let model = demoModel()
        let (client, info) = try await model.prepare(server: "demo.zammad.invalid")
        #expect(info.microsoft)
        #expect(try await model.signIn(client, username: "emma", password: "secret") == nil)
        #expect(model.me?.displayName == "Emma Taylor")
        guard case .session(let web) = client.credential else { Issue.record("no session"); return }
        #expect(web.csrf == "csrf-in" && web.cookies.map(\.value) == ["signedin"])
        // writes need the CSRF token of the signed-in session
        let article = try await client.post(ArticleDraft(ticketId: 2, body: "Thanks!", kind: .reply, to: nil))
        #expect(article.id == 33)
        Keychain.delete(account: client.baseURL.absoluteString)
    }

    @Test func wrongPasswordShowsServerMessage() async throws {
        let model = demoModel()
        let (client, _) = try await model.prepare(server: "https://demo.zammad.invalid/")
        await #expect(throws: ZammadError(message: "The username or password is incorrect.", status: 401)) {
            try await model.signIn(client, username: "emma", password: "nope")
        }
        #expect(model.client == nil)
    }

    @Test func twoFactorAsksForAppCodeThenSignsIn() async throws {
        let model = demoModel()
        let (client, _) = try await model.prepare(server: "demo.zammad.invalid")
        let method = try await model.signIn(client, username: "emma", password: "secret2fa")
        #expect(method == "authenticator_app")  // security keys are skipped, the app can't do WebAuthn
        #expect(model.client == nil)
        #expect(try await model.signIn(client, username: "emma", password: "secret2fa", twoFactor: (method!, "123456")) == nil)
        #expect(model.client != nil)
        Keychain.delete(account: client.baseURL.absoluteString)
    }

    @Test func cookiesSurviveKeychainRoundTrip() throws {
        let cookie = try #require(HTTPCookie(properties: [.name: "_zammad_session", .value: "v", .domain: "h.example.com", .path: "/",
                                                          .expires: Date(timeIntervalSince1970: 4_000_000_000), .secure: "TRUE"]))
        let data = try JSONEncoder().encode([StoredCookie(cookie)])
        let back = try #require(try JSONDecoder().decode([StoredCookie].self, from: data).first?.cookie)
        #expect(back.name == cookie.name && back.value == "v" && back.isSecure && back.expiresDate == cookie.expiresDate)
    }

    @Test func expiredCookieIsDropped() {
        let web = WebSession()
        let set = { (header: String) in
            web.absorb(HTTPURLResponse(url: Demo.server, statusCode: 200, httpVersion: nil, headerFields: ["Set-Cookie": header])!)
        }
        set("_zammad_session=a; path=/")
        #expect(web.cookies.map(\.value) == ["a"])
        set("_zammad_session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT")
        #expect(web.cookies.isEmpty)
    }

    @Test func microsoftStartPagePostsCSRFToken() {
        let html = MicrosoftSignInView.startPage(csrf: "a+b/\"c", fingerprint: "f", server: URL(string: "https://h.example.com/z")!)
        #expect(html.contains(#"action="https://h.example.com/z/auth/microsoft_office365""#))
        #expect(html.contains(#"name="authenticity_token" value="a+b/&quot;c""#))
    }

    @Test func htmlBecomesReadableText() throws {
        let article = try ZammadClient.decoder.decode([Article].self, from: Data(Demo.articles.utf8))[0]
        #expect(article.text.hasPrefix("Hi,\n\nplease send me:\n1 x Café Kopi susu\n4 x Viennese melange"))
        #expect(article.text.hasSuffix("75007 Paris\n\nDavid Bell"))
        #expect(HTML.plainText("<p>a &amp; b&nbsp;&lt;c&gt; &#228;&#x1F600;</p><style>x{}</style><p>d</p>") == "a & b <c> ä😀\n\nd")
    }
}
