import Foundation

/// Ticket as returned with `expand=true`: names (`state`, `priority`, ...) next to the ids.
struct Ticket: Codable, Identifiable, Hashable {
    let id: Int
    let number: String
    var title: String
    var stateId: Int
    var priorityId: Int
    var state: String?
    var priority: String?
    var group: String?
    var customer: String?
    var owner: String?
    var ownerId: Int?
    var groupId: Int?
    var articleCount: Int?
    var updatedAt: Date
}

struct Article: Codable, Identifiable, Hashable {
    let id: Int
    var from: String?
    var to: String?
    var subject: String?
    var body: String
    var contentType: String
    var `internal`: Bool
    var type: String?
    var sender: String?
    var createdBy: String?
    var createdAt: Date

    var text: String { contentType == "text/html" ? HTML.plainText(body) : body }
    var isCustomer: Bool { sender == "Customer" }
}

struct TicketState: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var active: Bool
}

struct TicketPriority: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var active: Bool
}

struct User: Codable, Identifiable, Hashable {
    let id: Int
    var firstname: String?
    var lastname: String?
    var email: String?
    var login: String?
    var active: Bool?
    var roles: [String]?
    var groupIds: [String: [String]]?

    /// Zammad's "nobody" owner: tickets without an owner belong to this system user.
    static let nobodyID = 1

    /// Agents who may own tickets of a group (needs "full" or "change" access there).
    func canOwn(groupID: Int?) -> Bool {
        guard active != false, roles?.contains("Agent") == true else { return false }
        guard let groupIds, let groupID else { return true }
        return groupIds[String(groupID)]?.contains { $0 == "full" || $0 == "change" } == true
    }

    var displayName: String {
        let name = [firstname, lastname].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (email ?? login ?? "#\(id)") : name
    }
}

/// Fields sent with `PUT /api/v1/tickets/{id}`; unset ones stay untouched on the server.
struct TicketChange: Encodable {
    var stateId: Int?
    var priorityId: Int?
    var ownerId: Int?
}

/// New article for `POST /api/v1/ticket_articles`.
struct ArticleDraft: Encodable {
    enum Kind: String, CaseIterable, Identifiable {
        case reply, note
        var id: Self { self }
        var label: String { self == .reply ? "Email Reply" : "Internal Note" }
        var symbol: String { self == .reply ? "arrowshape.turn.up.left" : "note.text" }
    }

    var ticketId: Int
    var body: String
    var type: String
    var `internal`: Bool
    var to: String?
    var contentType = "text/plain"
    var sender = "Agent"

    init(ticketId: Int, body: String, kind: Kind, to: String?) {
        self.ticketId = ticketId
        self.body = body
        self.type = kind == .reply ? "email" : "note"
        self.internal = kind == .note
        self.to = kind == .reply ? to : nil
    }
}

enum TicketFilter: String, CaseIterable, Identifiable {
    case open = "Open", mine = "Assigned to Me", all = "All"
    var id: Self { self }

    static let openStates = #"state.name:(new OR open OR "pending reminder" OR "pending close")"#

    /// Elasticsearch query string for `GET /api/v1/tickets/search`.
    func query(search: String, meID: Int?) -> String {
        let scope: String? = switch self {
        case .open: Self.openStates
        case .mine: "\(Self.openStates) AND owner_id:\(meID ?? 0)"
        case .all: nil
        }
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (text.isEmpty, scope) {
        case (true, nil): return "*"
        case (true, let scope?): return scope
        case (false, nil): return text
        case (false, let scope?): return "(\(text)) AND \(scope)"
        }
    }
}
