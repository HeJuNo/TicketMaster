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
    var createdAt: Date?
    var pendingTime: Date?
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
    var createdById: Int?
    var createdAt: Date

    /// Display name in `from`: "Name <address>" becomes "Name"; "Name via Group <address>" keeps its "via" part out.
    var fromName: String? {
        guard var name = from?.replacing(/\s*<[^>]*>/, with: "").trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\""))), !name.isEmpty else { return nil }
        name = name.replacing(/\s+via(\s.*)?$/, with: "")  // "Emma via Support <addr>" is sent on behalf of a group
        return name.isEmpty ? nil : name
    }

    var text: String { contentType == "text/html" ? HTML.plainText(body) : body }
    var isCustomer: Bool { sender == "Customer" }
}

struct TicketState: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var active: Bool

    /// "pending reminder" and "pending close" need a date: Zammad rejects them without `pending_time`.
    var needsPendingTime: Bool { name.lowercased().hasPrefix("pending") }
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

/// A Zammad overview (saved ticket filter) as listed in the web app's sidebar, with its ticket count.
struct Overview: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var prio: Int?
    var link: String
    var count: Int?
}

/// Answer of `GET /api/v1/ticket_overviews?view=<link>`: ticket ids in overview order, records in `assets`.
/// Assets carry ids only (no state or customer names), so the names are looked up here.
struct OverviewResult: Decodable {
    var assets: Assets
    var index: Index

    struct Index: Decodable { var tickets: [Ref] }
    struct Ref: Decodable { var id: Int }
    struct Assets: Decodable {
        var tickets: [String: Record]?
        var users: [String: User]?
        var groups: [String: Group]?
        enum CodingKeys: String, CodingKey { case tickets = "Ticket", users = "User", groups = "Group" }
    }
    struct Group: Decodable { var name: String }
    struct Record: Decodable {
        var id: Int
        var number: String
        var title: String
        var stateId: Int
        var priorityId: Int
        var groupId: Int?
        var ownerId: Int?
        var customerId: Int?
        var articleCount: Int?
        var createdAt: Date?
        var pendingTime: Date?
        var updatedAt: Date
    }

    func tickets(states: [TicketState], priorities: [TicketPriority]) -> [Ticket] {
        index.tickets.compactMap { ref in
            guard let r = assets.tickets?[String(ref.id)] else { return nil }
            return Ticket(
                id: r.id, number: r.number, title: r.title, stateId: r.stateId, priorityId: r.priorityId,
                state: states.first { $0.id == r.stateId }?.name, priority: priorities.first { $0.id == r.priorityId }?.name,
                group: r.groupId.flatMap { assets.groups?[String($0)]?.name },
                customer: r.customerId.flatMap { assets.users?[String($0)]?.displayName },
                owner: r.ownerId == User.nobodyID ? "-" : r.ownerId.flatMap { assets.users?[String($0)]?.displayName },
                ownerId: r.ownerId, groupId: r.groupId, articleCount: r.articleCount, createdAt: r.createdAt, pendingTime: r.pendingTime, updatedAt: r.updatedAt)
        }
    }
}

/// Fields sent with `PUT /api/v1/tickets/{id}`; unset ones stay untouched on the server.
struct TicketChange: Encodable {
    var stateId: Int?
    var priorityId: Int?
    var ownerId: Int?
    var pendingTime: Date?
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

/// Ways to order a ticket list. `server` keeps the order of the Zammad overview.
enum TicketSort: String, CaseIterable, Identifiable {
    case server = "Overview Order", updated = "Last Updated", created = "Created", number = "Number", priority = "Priority", title = "Title"
    var id: Self { self }

    /// Direction a freshly chosen sort starts in: newest and most urgent first, titles A to Z.
    var startsAscending: Bool { self == .title }

    func apply(_ tickets: [Ticket], ascending: Bool) -> [Ticket] {
        if self == .server { return tickets }
        let sorted: [Ticket] = switch self {
        case .server: tickets
        case .updated: tickets.sorted { $0.updatedAt < $1.updatedAt }
        case .created: tickets.sorted { ($0.createdAt ?? $0.updatedAt) < ($1.createdAt ?? $1.updatedAt) }
        case .number: tickets.sorted { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
        case .priority: tickets.sorted { ($0.priorityId, $0.updatedAt) < ($1.priorityId, $1.updatedAt) }  // same priority: by update time
        case .title: tickets.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return ascending ? sorted : sorted.reversed()
    }
}

extension Ticket {
    /// Search over what a row shows: title, number, customer, owner and group.
    func matches(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        let haystack = [title, number, customer, owner, group].compactMap { $0 }.joined(separator: " ")
        return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }
}
