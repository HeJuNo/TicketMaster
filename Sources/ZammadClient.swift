import Foundation

struct ZammadError: LocalizedError, Equatable {
    var message: String
    var status: Int? = nil
    var errorDescription: String? { message }
}

/// Signed-in web session, the same way the Zammad web app signs in (cookie + CSRF token).
/// Needs no API setting or token permission on the server.
final class WebSession {
    var cookies: [HTTPCookie]
    var csrf: String?

    init(cookies: [HTTPCookie] = []) { self.cookies = cookies }

    /// Takes over new cookies and the CSRF token that Zammad sends with every answer.
    func absorb(_ response: HTTPURLResponse) {
        if let token = response.value(forHTTPHeaderField: "CSRF-Token") { csrf = token }
        guard let url = response.url, let fields = response.allHeaderFields as? [String: String] else { return }
        merge(HTTPCookie.cookies(withResponseHeaderFields: fields, for: url))
    }

    func merge(_ new: [HTTPCookie]) {
        for cookie in new {
            cookies.removeAll { $0.name == cookie.name }
            if cookie.expiresDate.map({ $0 > .now }) ?? true { cookies.append(cookie) }  // past date = deleted
        }
    }
}

enum Credential {
    case token(String)
    case session(WebSession)
}

/// Zammad REST API (https://docs.zammad.org/en/latest/api/intro.html).
struct ZammadClient {
    let baseURL: URL
    let credential: Credential
    var urlSession: URLSession = Self.defaultSession

    /// Cookies are handled by `WebSession`, never by URLSession, so they can be stored in the keychain.
    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    /// Normalises user input to an https base URL; plain http would send the password in clear text.
    static func serverURL(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host() != nil else {
            throw ZammadError(message: "Enter the address of your Zammad server, starting with https://.")
        }
        return url
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func makeRequest(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable)? = nil) throws -> URLRequest {
        var url = baseURL.appending(path: "api/v1/" + path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch credential {
        case .token(let token):
            request.setValue("Token token=\(token)", forHTTPHeaderField: "Authorization")
        case .session(let web):
            HTTPCookie.requestHeaderFields(with: web.cookies).forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if let csrf = web.csrf { request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token") }
        }
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Raw call; keeps the web session up to date.
    func perform(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ZammadError(message: "No answer from the server.") }
        if case .session(let web) = credential { web.absorb(http) }
        return (data, http.statusCode)
    }

    static func errorMessage(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
    }

    func send<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> T {
        let (data, status) = try await perform(makeRequest(method, path, query: query, body: body))
        guard (200..<300).contains(status) else {
            let message = switch status {
            case 401: "You have been signed out. Please sign in again."
            case 403: Self.errorMessage(data) ?? "You don't have permission for this."
            default: Self.errorMessage(data) ?? "The server answered with status \(status)."
            }
            throw ZammadError(message: message, status: status)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw ZammadError(message: "Unexpected answer from the server (\(path)).")
        }
    }

    // MARK: Sign-in (web session)

    struct ServerInfo {
        var microsoft: Bool
    }

    /// Checks that the address is a Zammad server, starts an anonymous session and reads the offered sign-in methods.
    func signShow() async throws -> ServerInfo {
        let (data, status) = try await perform(makeRequest("GET", "signshow"))
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = json["config"] as? [String: Any] else {
            throw ZammadError(message: "No Zammad server found at this address.")
        }
        // Zammad only lists enabled sign-in providers to visitors who are not signed in.
        return ServerInfo(microsoft: config["auth_microsoft_office365"] as? Bool == true)
    }

    struct SignIn: Encodable {
        var username: String
        var password: String
        var rememberMe = true
        var fingerprint: String
        var twoFactorMethod: String?
        var twoFactorPayload: String?
    }

    /// Signs in with username and password. Returns the two-factor method to ask a code for, or nil when signed in.
    func signIn(_ form: SignIn) async throws -> String? {
        let (data, status) = try await perform(makeRequest("POST", "signin", body: form))
        if (200..<300).contains(status) { return nil }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let twoFactor = json?["two_factor_required"] as? [String: Any] {
            let available = twoFactor["available_two_factor_authentication_methods"] as? [String] ?? []
            let preferred = [twoFactor["default_two_factor_authentication_method"] as? String] + available.map(Optional.some)
            // Security keys need WebAuthn; codes from an authenticator app or a recovery code work natively.
            if let method = preferred.compactMap({ $0 }).first(where: { $0 == "authenticator_app" || $0 == "recovery_codes" }) {
                return method
            }
            throw ZammadError(message: "This account only allows sign-in with a security key. Use “Sign in with Browser”.")
        }
        throw ZammadError(message: Self.errorMessage(data) ?? "Sign-in failed (status \(status)).", status: status)
    }

    func signOut() async {
        _ = try? await perform(makeRequest("DELETE", "signout"))
    }

    // MARK: Endpoints

    func me() async throws -> User { try await send("users/me") }
    func states() async throws -> [TicketState] { try await send("ticket_states") }
    func priorities() async throws -> [TicketPriority] { try await send("ticket_priorities") }

    func searchTickets(_ query: String, limit: Int = 100) async throws -> [Ticket] {
        try await send("tickets/search", query: [
            .init(name: "query", value: query), .init(name: "limit", value: "\(limit)"),
            .init(name: "expand", value: "true"),
            .init(name: "sort_by", value: "updated_at"), .init(name: "order_by", value: "desc"),
        ])
    }

    func ticket(_ id: Int) async throws -> Ticket {
        try await send("tickets/\(id)", query: [.init(name: "expand", value: "true")])
    }

    func articles(ticket id: Int) async throws -> [Article] {
        try await send("ticket_articles/by_ticket/\(id)", query: [.init(name: "expand", value: "true")])
    }

    func post(_ draft: ArticleDraft) async throws -> Article {
        try await send("ticket_articles", method: "POST", query: [.init(name: "expand", value: "true")], body: draft)
    }

    func update(ticket id: Int, stateID: Int? = nil, priorityID: Int? = nil, ownerID: Int? = nil) async throws -> Ticket {
        try await send("tickets/\(id)", method: "PUT", query: [.init(name: "expand", value: "true")],
                       body: TicketChange(stateId: stateID, priorityId: priorityID, ownerId: ownerID))
    }

    /// Users with roles and group access; the caller keeps those who can own a ticket (`User.canOwn`).
    func users() async throws -> [User] {
        try await send("users/search", query: [.init(name: "query", value: "*"), .init(name: "limit", value: "200"),
                                               .init(name: "expand", value: "true")])
    }
}
