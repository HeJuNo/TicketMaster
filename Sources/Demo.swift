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
        case ("GET", "/api/v1/signshow") where signedIn || request.value(forHTTPHeaderField: "Authorization") == "Token token=demo":
            return (200, session, signedIn ? ["CSRF-Token": "csrf-in"] : [:])
        case ("GET", "/api/v1/signshow"):
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
        case ("GET", "/api/v1/users/search"): return (200, users, [:])
        case ("GET", "/api/v1/ticket_states"): return (200, states, [:])
        case ("GET", "/api/v1/ticket_priorities"): return (200, priorities, [:])
        case ("GET", "/api/v1/ticket_overviews"):
            let view = request.url?.query(percentEncoded: false)?.firstMatch(of: /view=(\w+)/).map { String($0.1) }
            switch view {
            case nil: return (200, overviews, [:])
            case "my_assigned": return (200, overviewView([2, 3]), [:])
            case "all_open": return (200, overviewView([1]), [:])
            default: return (404, #"{"error":"Not Found"}"#, [:])
            }
        case ("GET", "/api/v1/tickets/2"), ("PUT", "/api/v1/tickets/2"): return (200, tickets[1], [:])
        case ("GET", "/api/v1/ticket_articles/by_ticket/2"): return (200, articles, [:])
        case ("POST", "/api/v1/ticket_articles"): return (201, created, [:])
        default: return (404, #"{"error":"Not Found"}"#, [:])
        }
    }

    nonisolated static let me = #"{"id":3,"firstname":"Emma","lastname":"Taylor","email":"emma@chrispresso.com","login":"emma@chrispresso.com"}"#
    nonisolated static let session = #"""
    {"session":{"id":3,"firstname":"Emma","lastname":"Taylor","email":"emma@chrispresso.com","group_ids":{"1":["full"],"3":["full"]}},
     "config":{}}
    """#

    nonisolated static let overviews = #"""
    [{"id":2,"name":"Open","prio":1100,"link":"all_open","count":1},
     {"id":1,"name":"My assigned Tickets","prio":1000,"link":"my_assigned","count":2}]
    """#

    /// Shape of the real answer: ticket ids in `index`, records without names in `assets`.
    nonisolated static func overviewView(_ ids: [Int]) -> String {
        let records = [
            1: #""1":{"id":1,"number":"22001","title":"Welcome to Zammad!","state_id":1,"priority_id":2,"group_id":1,"owner_id":1,"customer_id":11,"article_count":1,"updated_at":"2026-11-13T08:51:13.809Z"}"#,
            2: #""2":{"id":2,"number":"22002","title":"Order 777555","state_id":2,"priority_id":2,"group_id":1,"owner_id":3,"customer_id":10,"article_count":2,"created_at":"2026-11-01T10:00:00.000Z","updated_at":"2026-11-13T07:57:17.927Z"}"#,
            3: #""3":{"id":3,"number":"22003","title":"Espresso machine leaks water","state_id":3,"priority_id":2,"group_id":3,"owner_id":3,"customer_id":12,"article_count":2,"updated_at":"2026-11-12T16:20:00.000Z"}"#,
        ]
        return #"""
        {"assets":{"Ticket":{\#(ids.compactMap { records[$0] }.joined(separator: ","))},
          "User":{"3":{"id":3,"firstname":"Emma","lastname":"Taylor","email":"emma@chrispresso.com"},
                  "10":{"id":10,"firstname":"David","lastname":"Bell","email":"david@example.com"},
                  "11":{"id":11,"firstname":"Nicole","lastname":"Braun","email":"nicole.braun@zammad.org"},
                  "12":{"id":12,"firstname":"","lastname":"","email":"lena@example.com"}},
          "Group":{"1":{"id":1,"name":"Sales"},"3":{"id":3,"name":"Service Desk"}}},
         "index":{"overview":{"id":1},"count":\#(ids.count),"tickets":[\#(ids.map { #"{"id":\#($0),"updated_at":"2026-11-13T08:00:00.000Z"}"# }.joined(separator: ","))]}}
        """#
    }

    nonisolated static let users = #"""
    [\#(me.dropLast()),"active":true,"roles":["Agent"],"group_ids":{"1":["full"]}},
     {"id":4,"firstname":"Chris","lastname":"Miller","email":"chris@chrispresso.com","active":true,"roles":["Admin","Agent"],"group_ids":{"1":["read","change"]}},
     {"id":5,"firstname":"Ben","lastname":"Reader","email":"ben@chrispresso.com","active":true,"roles":["Agent"],"group_ids":{"1":["read"]}},
     {"id":6,"firstname":"Olga","lastname":"Other","email":"olga@chrispresso.com","active":true,"roles":["Agent"],"group_ids":{"2":["full"]}},
     {"id":7,"firstname":"Gone","lastname":"Agent","email":"gone@chrispresso.com","active":false,"roles":["Agent"],"group_ids":{"1":["full"]}},
     {"id":10,"firstname":"David","lastname":"Bell","email":"david@example.com","active":true,"roles":["Customer"]}]
    """#

    nonisolated static let states = #"""
    [{"id":1,"name":"new","active":true},{"id":2,"name":"open","active":true},{"id":3,"name":"pending reminder","active":true},
     {"id":4,"name":"closed","active":true},{"id":5,"name":"merged","active":false},{"id":7,"name":"pending close","active":true}]
    """#
    nonisolated static let priorities = #"[{"id":1,"name":"1 low","active":true},{"id":2,"name":"2 normal","active":true},{"id":3,"name":"3 high","active":true}]"#

    nonisolated static let tickets = [
        ticket(1, "Welcome to Zammad!", state: (1, "new"), customer: "nicole.braun@zammad.org", owner: "-", updated: "2026-11-13T08:51:13.809Z"),
        ticket(2, "Order 777555", state: (2, "open"), customer: "david@example.com", owner: "emma@chrispresso.com", updated: "2026-11-13T07:57:17.927Z"),
        ticket(3, "Espresso machine leaks water", state: (3, "pending reminder"), customer: "lena@example.com", owner: "emma@chrispresso.com", updated: "2026-11-12T16:20:00.000Z", group: (3, "Service Desk")),
        ticket(4, "Invoice 2026-118 missing", state: (2, "open"), customer: "accounting@example.org", owner: "-", updated: "2026-11-10T09:03:41.120Z", group: (3, "Service Desk")),
    ]

    nonisolated static func ticket(_ id: Int, _ title: String, state: (Int, String), customer: String, owner: String, updated: String,
                                   group: (Int, String) = (1, "Sales")) -> String {
        #"{"id":\#(id),"number":"2200\#(id)","title":"\#(title)","state_id":\#(state.0),"state":"\#(state.1)","priority_id":2,"priority":"2 normal","group":"\#(group.1)","customer":"\#(customer)","owner":"\#(owner)","owner_id":\#(owner == "-" ? 1 : 3),"group_id":\#(group.0),"article_count":2,"created_at":"2026-11-01T11:51:13.759Z","updated_at":"\#(updated)"}"#
    }

    nonisolated static let articles = #"""
    [{"id":9,"ticket_id":2,"from":"David Bell <david@example.com>","to":"order@chrispresso.com","subject":null,"content_type":"text/html",
      "body":"Hi,<br>\n<br>\n<u>please send me:</u><br>\n1 x Café Kopi susu<br>\n4 x Viennese melange<br>\n<br>\n<u>Delivery Address:</u><br>\nDavid Bell<br>\nEiffel Tower<br>\n5 Avenue Anatole France<br>\n75007 Paris<br>\n<span class=\"js-signatureMarker\"></span>\n<br>\nDavid Bell",
      "internal":false,"type":"email","sender":"Customer","created_by":"david@example.com","created_by_id":10,"created_at":"2026-11-12T11:57:18.068Z"},
     {"id":10,"ticket_id":2,"from":"Emma Taylor","to":null,"subject":null,"content_type":"text/plain",
      "body":"Melange is out of stock until Monday – ask David whether he wants to wait.","internal":true,"type":"note","sender":"Agent",
      "created_by":"emma@chrispresso.com","created_by_id":3,"created_at":"2026-11-12T13:02:00.000Z"},
     {"id":11,"ticket_id":2,"from":"Emma Taylor via <order@chrispresso.com>","to":"David Bell <david@example.com>","subject":null,"content_type":"text/html",
      "body":"<p>Hi David,</p><p>nice, we will ship it to your delivery address. You will get it till Wednesday.</p><p>--<br>Greetings,<br>Emma Taylor</p><div class=\"gmail_quote\"><div>On Thu, Nov 12, 2026 at 12:57 PM David Bell &lt;david@example.com&gt; wrote:</div><blockquote><p>Hi, please send me 1 x Café Kopi susu and 4 x Viennese melange.</p></blockquote></div>",
      "internal":false,"type":"email","sender":"Agent","created_by":"emma@chrispresso.com","created_by_id":3,"created_at":"2026-11-13T07:57:18.121Z"}]
    """#

    nonisolated static let created = #"{"id":33,"ticket_id":2,"from":"Emma Taylor","to":"David Bell <david@example.com>","subject":null,"content_type":"text/plain","body":"Thanks!","internal":false,"type":"email","sender":"Agent","created_by":"emma@chrispresso.com","created_by_id":3,"created_at":"2026-11-13T09:00:00.000Z"}"#
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
