import SwiftUI

struct TicketListView: View {
    @Environment(AppModel.self) private var model
    let overview: Overview
    @Binding var selection: Ticket?
    @AppStorage("ticketSort") private var sort = TicketSort.server
    @AppStorage("ticketSortAscending") private var ascending = false
    @State private var search = ""
    @State private var tickets: [Ticket] = []
    @State private var loaded = false
    @State private var error: String?

    private var shown: [Ticket] {
        let found = search.trimmingCharacters(in: .whitespaces).isEmpty ? tickets : tickets.filter { $0.matches(search) }
        return sort.apply(found, ascending: ascending)
    }

    var body: some View {
        List(shown, selection: $selection) { ticket in
            NavigationLink(value: ticket) { TicketRow(ticket: ticket) }
                .listRowInsets(EdgeInsets())
                .swipeActions(edge: .leading) {
                    if let me = model.me, ticket.ownerId != me.id {
                        Button("Assign to Me", systemImage: "person.crop.circle.badge.checkmark") { Task { await assign(ticket, to: me) } }
                            .tint(.blue)
                    }
                }
        }
        .overlay {
            if let error, tickets.isEmpty {
                ContentUnavailableView("Can't Load Tickets", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if loaded, tickets.isEmpty {
                ContentUnavailableView("No Tickets", systemImage: "tray", description: Text("Nothing in “\(overview.name)”."))
            } else if loaded, shown.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if !loaded {
                ProgressView()
            }
        }
        .navigationTitle(overview.name)
        .navigationSubtitle(loaded ? "\(shown.count) of \(tickets.count) tickets" : "")
        .searchable(text: $search, prompt: "Search These Tickets")
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(TicketSort.allCases) { option in
                        Button {
                            if sort == option, option != .server { ascending.toggle() } else { sort = option; ascending = option.startsAscending }
                        } label: {
                            if sort == option, option != .server {
                                Label(option.rawValue, systemImage: ascending ? "chevron.up" : "chevron.down")
                            } else if sort == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func assign(_ ticket: Ticket, to me: User) async {
        guard let client = model.client, let updated = try? await client.update(ticket: ticket.id, ownerID: me.id),
              let index = tickets.firstIndex(where: { $0.id == ticket.id }) else { return }
        tickets[index] = updated
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            tickets = try await client.tickets(in: overview, states: model.states, priorities: model.priorities)
            error = nil
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch let zammad as ZammadError where zammad.status == 401 {
            model.signOut()  // session expired on the server
            return
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

struct TicketRow: View {
    let ticket: Ticket

    private var unassigned: Bool { ticket.ownerId == User.nobodyID || ticket.owner == "-" }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(StateColor.color(for: ticket.state)).frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(ticket.number)").monospacedDigit()
                    if let group = ticket.group { Text("· \(group)").lineLimit(1) }
                    Spacer()
                    Text(ticket.updatedAt, format: .relative(presentation: .named))
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(ticket.title).font(.headline).lineLimit(2)
                HStack(spacing: 8) {
                    StateBadge(state: ticket.state)
                    if let priority = ticket.priority, PriorityLabel.isHigh(priority) { PriorityLabel(name: priority, compact: true) }
                    if let customer = ticket.customer { Text(customer).lineLimit(1) }
                    Spacer(minLength: 4)
                    if unassigned {
                        Text("Unassigned").foregroundStyle(.orange)
                    } else if let owner = ticket.owner {
                        Label(owner, systemImage: "person.fill").labelStyle(.titleAndIcon).lineLimit(1)
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.trailing, 16)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Priority as text; high and urgent ones stand out in red. Names are the server's ("2 normal", "3 high").
struct PriorityLabel: View {
    let name: String
    var compact = false

    static func isHigh(_ name: String) -> Bool { ["high", "urgent"].contains { name.localizedCaseInsensitiveContains($0) } }

    var body: some View {
        if Self.isHigh(name) {
            Label(compact ? "" : name, systemImage: "exclamationmark.2").foregroundStyle(.red).font(.caption.weight(.semibold))
                .accessibilityLabel(name)
        } else if !compact {
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }
}

enum StateColor {
    static func color(for state: String?) -> Color {
        switch state {
        case "new": .blue
        case "open": .orange
        case let s? where s.hasPrefix("pending"): .purple
        case "closed": .green
        default: .gray
        }
    }
}

struct StateBadge: View {
    let state: String?

    var body: some View {
        Text((state ?? "unknown").capitalized)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }

    private var color: Color { StateColor.color(for: state) }
}
