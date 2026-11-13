import Foundation

struct ZammadError: LocalizedError, Equatable {
    var message: String
    var errorDescription: String? { message }
}

/// Zammad REST API (https://docs.zammad.org/en/latest/api/intro.html) with a personal access token.
struct ZammadClient {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    /// Normalises user input to an https base URL; plain http would send the token in clear text.
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
        request.setValue("Token token=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func send<T: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> T {
        let (data, response) = try await session.data(for: makeRequest(method, path, query: query, body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            let message = switch status {
            case 401: "The token was rejected. Check it under Profile > Token Access in Zammad."
            case 403: serverMessage ?? "You don't have permission for this."
            default: serverMessage ?? "The server answered with status \(status)."
            }
            throw ZammadError(message: message)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw ZammadError(message: "Unexpected answer from the server (\(path)).")
        }
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

    func update(ticket id: Int, stateID: Int? = nil, priorityID: Int? = nil) async throws -> Ticket {
        struct Change: Encodable { var stateId: Int?; var priorityId: Int? }
        return try await send("tickets/\(id)", method: "PUT", query: [.init(name: "expand", value: "true")],
                              body: Change(stateId: stateID, priorityId: priorityID))
    }
}
