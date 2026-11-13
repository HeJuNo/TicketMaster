import SwiftUI

struct TicketListView: View {
    @Environment(AppModel.self) private var model
    let queue: Queue
    @Binding var selection: Ticket?
    @SceneStorage("filter") private var filter = TicketFilter.open
    @State private var search = ""
    @State private var tickets: [Ticket] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List(tickets, selection: $selection) { ticket in
            NavigationLink(value: ticket) { TicketRow(ticket: ticket) }
        }
        .overlay {
            if let error, tickets.isEmpty {
                ContentUnavailableView("Can't Load Tickets", systemImage: "wifi.exclamationmark", description: Text(error))
            } else if loaded, tickets.isEmpty, !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if loaded, tickets.isEmpty {
                ContentUnavailableView("No Tickets", systemImage: "tray", description: Text("Nothing in “\(filter.rawValue)”."))
            } else if !loaded {
                ProgressView()
            }
        }
        .navigationTitle(queue.title)
        .navigationSubtitle(filter.rawValue)
        .searchable(text: $search, prompt: "Search Tickets")
        .refreshable { await load() }
        .task(id: "\(filter.rawValue)|\(search)") {
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }  // debounce typing
            guard !Task.isCancelled else { return }
            await load()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(TicketFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            tickets = try await client.searchTickets(filter.query(search: search, meID: model.me?.id, groupID: queue.groupID))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(ticket.title).font(.headline).lineLimit(2)
                Spacer()
                Text(ticket.updatedAt, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                StateBadge(state: ticket.state)
                Text("#\(ticket.number)").monospacedDigit()
                if let customer = ticket.customer { Text("· \(customer)").lineLimit(1) }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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

    private var color: Color {
        switch state {
        case "new": .blue
        case "open": .orange
        case let s? where s.hasPrefix("pending"): .purple
        case "closed": .green
        default: .gray
        }
    }
}
