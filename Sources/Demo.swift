#if DEBUG
import Foundation

/// Canned Zammad answers for the simulator (`-demo YES`) and the tests. Shapes follow docs.zammad.org.
enum Demo {
    nonisolated static let server = URL(string: "https://demo.zammad.invalid")!
    static var client: ZammadClient { ZammadClient(baseURL: server, token: "demo", session: FixtureProtocol.session) }

    nonisolated static func respond(to request: URLRequest) -> (Int, String) {
        let path = request.url?.path() ?? ""
        switch (request.httpMethod ?? "GET", path) {
        case (_, _) where request.value(forHTTPHeaderField: "Authorization") != "Token token=demo":
            return (401, #"{"error":"authentication failed"}"#)
        case ("GET", "/api/v1/users/me"): return (200, me)
        case ("GET", "/api/v1/ticket_states"): return (200, states)
        case ("GET", "/api/v1/ticket_priorities"): return (200, priorities)
        case ("GET", "/api/v1/tickets/search"): return (200, "[\(tickets.joined(separator: ","))]")
        case ("GET", "/api/v1/tickets/2"), ("PUT", "/api/v1/tickets/2"): return (200, tickets[1])
        case ("GET", "/api/v1/ticket_articles/by_ticket/2"): return (200, articles)
        case ("POST", "/api/v1/ticket_articles"): return (201, created)
        default: return (404, #"{"error":"Not Found"}"#)
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
        let (status, body) = Demo.respond(to: request)
        let response = HTTPURLResponse(url: request.url ?? Demo.server, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    nonisolated override func stopLoading() {}
}
#endif
