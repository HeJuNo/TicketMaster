#if DEBUG
import Foundation

/// Canned Zammad answers for the simulator (`-demo YES`) and the tests. Shapes follow docs.zammad.org.
enum Demo {
    nonisolated static let server = URL(string: "https://demo.zammad.invalid")!
    static var client: ZammadClient { ZammadClient(baseURL: server, credential: .token("demo"), urlSession: FixtureProtocol.session) }

    /// Status, body and extra headers. Sign-in follows Zammad: emma / secret, or emma / secret2fa plus code 123456.
    nonisolated static func respond(to request: URLRequest, body: Data?) -> (Int, String, [String: String]) {
        let path = request.url?.path() ?? ""
        let method = request.httpMethod ?? "GET"
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let csrf = request.value(forHTTPHeaderField: "X-CSRF-Token")
        let signedIn = cookie.contains("_zammad_session=signedin")
        let anon = ["Set-Cookie": "_zammad_session=anon; path=/; secure; HttpOnly", "CSRF-Token": "csrf-anon"]
        switch (method, path) {
        case ("GET", "/api/v1/signshow") where !signedIn:
            return (200, #"{"error":"no valid session","config":{"product_name":"Zammad","auth_microsoft_office365":true}}"#, anon)
        case ("POST", "/api/v1/signin"):
            guard cookie.contains("_zammad_session=anon"), csrf == "csrf-anon" else { return (401, #"{"error":"CSRF token verification failed!"}"#, [:]) }
            let form = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let password = form["password"] as? String
            guard form["username"] as? String == "emma", password == "secret" || password == "secret2fa" else {
                return (401, #"{"error":"The username or password is incorrect."}"#, [:])
            }
            if password == "secret2fa", form["two_factor_payload"] as? String != "123456" {
                return (422, #"{"two_factor_required":{"default_two_factor_authentication_method":"security_keys","available_two_factor_authentication_methods":["security_keys","authenticator_app"],"recovery_codes_available":true}}"#, [:])
            }
            return (201, #"{"session":\#(me)}"#, ["Set-Cookie": "_zammad_session=signedin; path=/; expires=Fri, 13 Nov 2099 10:00:00 GMT; secure; HttpOnly", "CSRF-Token": "csrf-in"])
        case ("DELETE", "/api/v1/signout"):
            return (200, "{}", ["Set-Cookie": "_zammad_session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT"])
        case (_, _) where request.value(forHTTPHeaderField: "Authorization") != "Token token=demo" && !signedIn:
            return (401, #"{"error":"authentication failed"}"#, [:])
        case (_, _) where signedIn && method != "GET" && csrf != "csrf-in":
            return (401, #"{"error":"CSRF token verification failed!"}"#, [:])
        case ("GET", "/api/v1/users/me"): return (200, me, signedIn ? ["CSRF-Token": "csrf-in"] : [:])
        case ("GET", "/api/v1/ticket_states"): return (200, states, [:])
        case ("GET", "/api/v1/ticket_priorities"): return (200, priorities, [:])
        case ("GET", "/api/v1/tickets/search"): return (200, "[\(tickets.joined(separator: ","))]", [:])
        case ("GET", "/api/v1/tickets/2"), ("PUT", "/api/v1/tickets/2"): return (200, tickets[1], [:])
        case ("GET", "/api/v1/ticket_articles/by_ticket/2"): return (200, articles, [:])
        case ("POST", "/api/v1/ticket_articles"): return (201, created, [:])
        default: return (404, #"{"error":"Not Found"}"#, [:])
        }
    }

    nonisolated static let me = #"{"id":3,"firstname":"Emma","lastname":"Taylor","email":"emma@chrispresso.com","login":"emma@chrispresso.com"}"#
    nonisolated static let states = #"""
    [{"id":1,"name":"new","active":true},{"id":2,"name":"open","active":true},{"id":3,"name":"pending reminder","active":true},
     {"id":4,"name":"closed","active":true},{"id":5,"name":"merged","active":false},{"id":7,"name":"pending close","active":true}]
    """#
    nonisolated static let priorities = #"[{"id":1,"name":"1 low","active":true},{"id":2,"name":"2 normal","active":true},{"id":3,"name":"3 high","active":true}]"#

    nonisolated static let tickets = [
        ticket(1, "Welcome to Zammad!", state: (1, "new"), customer: "nicole.braun@zammad.org", owner: "-", updated: "2026-11-13T08:51:13.809Z"),
        ticket(2, "Order 777555", state: (2, "open"), customer: "david@example.com", owner: "emma@chrispresso.com", updated: "2026-11-13T07:57:17.927Z"),
        ticket(3, "Espresso machine leaks water", state: (3, "pending reminder"), customer: "lena@example.com", owner: "emma@chrispresso.com", updated: "2026-11-12T16:20:00.000Z"),
        ticket(4, "Invoice 2026-118 missing", state: (2, "open"), customer: "accounting@example.org", owner: "-", updated: "2026-11-10T09:03:41.120Z"),
    ]

    nonisolated static func ticket(_ id: Int, _ title: String, state: (Int, String), customer: String, owner: String, updated: String) -> String {
        #"{"id":\#(id),"number":"2200\#(id)","title":"\#(title)","state_id":\#(state.0),"state":"\#(state.1)","priority_id":2,"priority":"2 normal","group":"Sales","customer":"\#(customer)","owner":"\#(owner)","article_count":2,"created_at":"2026-11-01T11:51:13.759Z","updated_at":"\#(updated)"}"#
    }

    nonisolated static let articles = #"""
    [{"id":9,"ticket_id":2,"from":"David Bell <david@example.com>","to":"order@chrispresso.com","subject":null,"content_type":"text/html",
      "body":"Hi,<br>\n<br>\n<u>please send me:</u><br>\n1 x Café Kopi susu<br>\n4 x Viennese melange<br>\n<br>\n<u>Delivery Address:</u><br>\nDavid Bell<br>\nEiffel Tower<br>\n5 Avenue Anatole France<br>\n75007 Paris<br>\n<span class=\"js-signatureMarker\"></span>\n<br>\nDavid Bell",
      "internal":false,"type":"email","sender":"Customer","created_by":"david@example.com","created_at":"2026-11-12T11:57:18.068Z"},
     {"id":10,"ticket_id":2,"from":"Emma Taylor","to":null,"subject":null,"content_type":"text/plain",
      "body":"Melange is out of stock until Monday – ask David whether he wants to wait.","internal":true,"type":"note","sender":"Agent",
      "created_by":"emma@chrispresso.com","created_at":"2026-11-12T13:02:00.000Z"},
     {"id":11,"ticket_id":2,"from":"Emma Taylor via <order@chrispresso.com>","to":"David Bell <david@example.com>","subject":null,"content_type":"text/html",
      "body":"<p>Hi David,</p><p>nice, we will ship it to your delivery address. You will get it till Wednesday.</p><p>--<br>Greetings,<br>Emma Taylor</p>",
      "internal":false,"type":"email","sender":"Agent","created_by":"emma@chrispresso.com","created_at":"2026-11-13T07:57:18.121Z"}]
    """#

    nonisolated static let created = #"{"id":33,"ticket_id":2,"from":"Emma Taylor","to":"David Bell <david@example.com>","subject":null,"content_type":"text/plain","body":"Thanks!","internal":false,"type":"email","sender":"Agent","created_by":"emma@chrispresso.com","created_at":"2026-11-13T09:00:00.000Z"}"#
}

/// Serves `Demo.respond(to:)` instead of the network.
nonisolated final class FixtureProtocol: URLProtocol {
    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return URLSession(configuration: config)
    }

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        let (status, body, headers) = Demo.respond(to: request, body: request.httpBody ?? request.httpBodyStream.map(Self.read))
        let response = HTTPURLResponse(url: request.url ?? Demo.server, statusCode: status, httpVersion: nil,
                                       headerFields: headers.merging(["Content-Type": "application/json"]) { a, _ in a })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    nonisolated override func stopLoading() {}

    /// URLSession hands bodies to protocols as a stream.
    nonisolated static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
#endif
