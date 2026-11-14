import SwiftUI

struct TicketDetailView: View {
    @Environment(AppModel.self) private var model
    @State var ticket: Ticket
    @State private var articles: [Article] = []
    @State private var draft = ""
    @State private var kind = ArticleDraft.Kind.reply
    @State private var sending = false
    @State private var error: String?
    @State private var pendingState: TicketState?
    @State private var pendingDate = Date()
    @AppStorage("showTicketDetails") private var showDetails = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(articles) { ArticleView(article: $0, author: author(of: $0)).id($0.id) }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)  // open at the newest article; the header is one swipe up
            .onChange(of: articles.count) { old, _ in
                if old > 0, let id = articles.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }  // own reply appended
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle("#\(ticket.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $pendingState) { state in pendingSheet(state) }
        .alert("Something Went Wrong", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ticket.title).font(.title2.bold())
            HStack(spacing: 8) {
                StateBadge(state: ticket.state)
                if let priority = ticket.priority { PriorityLabel(name: priority) }
                Spacer()
                Text("\(articles.count) \(articles.count == 1 ? "article" : "articles")").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Details", isExpanded: $showDetails) {
                VStack(spacing: 6) {
                    LabeledContent("Customer", value: ticket.customer ?? "–")
                    LabeledContent("Group", value: ticket.group ?? "–")
                    LabeledContent("Owner", value: isUnassigned ? "Unassigned" : ticket.owner ?? "–")
                    if let pending = ticket.pendingTime, ticket.state?.hasPrefix("pending") == true {
                        LabeledContent("Pending Until") { Text(pending, format: .dateTime.day().month().year().hour().minute()) }
                    }
                    LabeledContent("Updated") { Text(ticket.updatedAt, format: .dateTime.day().month().year().hour().minute()) }
                }
                .padding(.top, 6)
            }
            .font(.subheadline)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private var isUnassigned: Bool { ticket.ownerId == User.nobodyID || ticket.owner == "-" }
    private var isMine: Bool { ticket.ownerId != nil && ticket.ownerId == model.me?.id }

    /// Agents for the "Assign to" list: those with access to the ticket's group, and always the user themselves.
    private var assignable: [User] {
        var list = model.agents.filter { $0.canOwn(groupID: ticket.groupId) && $0.id != model.me?.id }
        list.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return list
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Owner") {
                    if let me = model.me, !isMine {
                        Button("Assign to Me", systemImage: "person.crop.circle.badge.checkmark") { Task { await change(ownerID: me.id) } }
                    }
                    if !assignable.isEmpty {
                        Menu("Assign to…", systemImage: "person.2") {
                            ForEach(assignable) { agent in
                                Button(agent.displayName) { Task { await change(ownerID: agent.id) } }
                                    .disabled(agent.id == ticket.ownerId)
                            }
                        }
                    }
                    if !isUnassigned {
                        Button("Unassign", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                            Task { await change(ownerID: User.nobodyID) }
                        }
                    }
                }
                Picker("State", selection: Binding(get: { ticket.stateId }, set: { id in chooseState(id) })) {
                    ForEach(model.states) { Text($0.name.capitalized).tag($0.id) }
                }
                Picker("Priority", selection: Binding(get: { ticket.priorityId }, set: { id in Task { await change(priorityID: id) } })) {
                    ForEach(model.priorities) { Text($0.name).tag($0.id) }
                }
            } label: {
                Label("Change State, Priority or Owner", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $kind) {
                ForEach(ArticleDraft.Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(alignment: .bottom, spacing: 8) {
                TextField(kind == .reply ? "Write a reply…" : "Write an internal note…", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(kind == .note ? Color.orange.opacity(0.12) : Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: sending ? "ellipsis.circle.fill" : "arrow.up.circle.fill").font(.system(size: 34))
                }
                .tint(kind == .note ? .orange : .accentColor)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
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
        // Optional: without permission to list users, "Assign to Me" and "Unassign" still work.
        await model.loadAgents()
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

    /// Who wrote an article: the agent's name for agent articles, else the sender's name from the mail header.
    private func author(of article: Article) -> String {
        if let id = article.createdById, let user = model.agents.first(where: { $0.id == id }) { return user.displayName }
        return article.isCustomer ? (article.fromName ?? article.createdBy ?? "Customer") : (article.createdBy ?? article.fromName ?? "Agent")
    }

    /// Pending states need a date; everything else is changed right away.
    private func chooseState(_ id: Int) {
        guard let state = model.states.first(where: { $0.id == id }) else { return }
        if state.needsPendingTime {
            pendingDate = ticket.pendingTime.flatMap { $0 > .now ? $0 : nil } ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            pendingState = state
        } else {
            Task { await change(stateID: id) }
        }
    }

    private func pendingSheet(_ state: TicketState) -> some View {
        NavigationStack {
            Form {
                DatePicker("Remind on", selection: $pendingDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
            }
            .navigationTitle(state.name.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { pendingState = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        pendingState = nil
                        Task { await change(stateID: state.id, pendingTime: pendingDate) }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func change(stateID: Int? = nil, priorityID: Int? = nil, ownerID: Int? = nil, pendingTime: Date? = nil) async {
        guard let client = model.client else { return }
        do {
            ticket = try await client.update(ticket: ticket.id, stateID: stateID, priorityID: priorityID, ownerID: ownerID, pendingTime: pendingTime)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ArticleView: View {
    let article: Article
    let author: String
    private let parts: BodyParts
    @State private var showQuoted = false

    init(article: Article, author: String) {
        self.article = article
        self.author = author
        parts = article.parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(author, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(article.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if article.internal { Label("Internal Note", systemImage: "lock.fill").foregroundStyle(.orange) }
                else if let sender = article.sender { Text(sender) }
                if let from = article.from, !article.internal, from != author { Text("· \(from)").lineLimit(1).truncationMode(.middle) }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let to = article.to, !article.internal { Text("To: \(to)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            Text(parts.main).textSelection(.enabled)
            if !parts.quoted.isEmpty {
                Button(showQuoted ? "Hide Earlier Messages" : "Show Earlier Messages", systemImage: showQuoted ? "chevron.up" : "ellipsis") {
                    withAnimation { showQuoted.toggle() }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                if showQuoted {
                    Text(parts.quoted).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 2) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: .rect(cornerRadius: 16))
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
