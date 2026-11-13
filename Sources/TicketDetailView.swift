import SwiftUI

struct TicketDetailView: View {
    @Environment(AppModel.self) private var model
    @State var ticket: Ticket
    @State private var articles: [Article] = []
    @State private var draft = ""
    @State private var kind = ArticleDraft.Kind.reply
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(articles) { ArticleView(article: $0).id($0.id) }
                }
                .padding()
            }
            .onChange(of: articles.last?.id) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("#\(ticket.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .refreshable { await load() }
        .task { await load() }
        .alert("Something Went Wrong", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ticket.title).font(.title2.bold())
            HStack(spacing: 8) {
                StateBadge(state: ticket.state)
                if let priority = ticket.priority { Text(priority).font(.caption).foregroundStyle(.secondary) }
            }
            LabeledContent("Customer", value: ticket.customer ?? "–")
            LabeledContent("Group", value: ticket.group ?? "–")
            LabeledContent("Owner", value: ticket.owner == "-" ? "Unassigned" : ticket.owner ?? "–")
        }
        .font(.subheadline)
        .padding(.bottom, 8)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("State", selection: Binding(get: { ticket.stateId }, set: { id in Task { await change(stateID: id) } })) {
                    ForEach(model.states) { Text($0.name.capitalized).tag($0.id) }
                }
                Picker("Priority", selection: Binding(get: { ticket.priorityId }, set: { id in Task { await change(priorityID: id) } })) {
                    ForEach(model.priorities) { Text($0.name).tag($0.id) }
                }
            } label: {
                Label("Change State or Priority", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Picker("Type", selection: $kind) {
                    ForEach(ArticleDraft.Kind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                Image(systemName: kind.symbol).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Article Type: \(kind.label)")
            TextField(kind.label, text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.vertical, 8)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: sending ? "ellipsis" : "arrow.up").font(.body.bold()).frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .glassEffect(in: .rect(cornerRadius: 24))
        .padding(.horizontal).padding(.bottom, 8)
    }

    /// Replies go to whoever last wrote as customer, as in the Zammad web app.
    private var replyAddress: String? {
        articles.last(where: \.isCustomer)?.from ?? ticket.customer
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            async let t = client.ticket(ticket.id)
            async let a = client.articles(ticket: ticket.id)
            (ticket, articles) = try await (t, a)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send() async {
        guard let client = model.client else { return }
        sending = true
        defer { sending = false }
        do {
            let article = try await client.post(ArticleDraft(ticketId: ticket.id, body: draft, kind: kind, to: replyAddress))
            articles.append(article)
            draft = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func change(stateID: Int? = nil, priorityID: Int? = nil) async {
        guard let client = model.client else { return }
        do {
            ticket = try await client.update(ticket: ticket.id, stateID: stateID, priorityID: priorityID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ArticleView: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(article.from ?? article.createdBy ?? "Unknown", systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(article.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            if article.internal {
                Label("Internal", systemImage: "lock.fill").font(.caption.weight(.medium)).foregroundStyle(.orange)
            }
            Text(article.text).textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch article.type {
        case "email": "envelope"
        case "phone": "phone"
        case "note": "note.text"
        case "web": "globe"
        default: "text.bubble"
        }
    }

    private var background: Color {
        if article.internal { return .orange.opacity(0.12) }
        return article.isCustomer ? Color(.secondarySystemBackground) : .accentColor.opacity(0.10)
    }
}
