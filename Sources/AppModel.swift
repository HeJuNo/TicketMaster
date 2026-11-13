import Foundation
import Observation

@Observable final class AppModel {
    var client: ZammadClient?
    var me: User?
    var states: [TicketState] = []
    var priorities: [TicketPriority] = []
    var overviews: [Overview] = []
    /// Loaded once on first use; every ticket's assign menu needs it.
    var agents: [User] = []
    /// Replaced by canned answers in debug demo runs.
    var urlSession = ZammadClient.defaultSession

    private static let serverKey = "server"

    /// Identifies this device in Zammad's device log, like the browser fingerprint of the web app.
    static var fingerprint: String {
        if let value = UserDefaults.standard.string(forKey: "fingerprint") { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: "fingerprint")
        return value
    }

    /// Continues the session from last time, if Zammad still accepts it.
    func restore() async {
        guard client == nil, let server = UserDefaults.standard.string(forKey: Self.serverKey),
              let url = URL(string: server), let data = Keychain.load(account: server),
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data) else { return }
        let web = WebSession(cookies: stored.compactMap(\.cookie))
        try? await finish(ZammadClient(baseURL: url, credential: .session(web), urlSession: urlSession))
    }

    /// Step 1 of sign-in: a fresh web session for the server, plus the sign-in methods it offers.
    func prepare(server: String) async throws -> (ZammadClient, ZammadClient.ServerInfo) {
        let client = ZammadClient(baseURL: try ZammadClient.serverURL(server), credential: .session(WebSession()), urlSession: urlSession)
        return (client, try await client.signShow())
    }

    /// Step 2: username and password. Returns the two-factor method when Zammad asks for a code.
    func signIn(_ client: ZammadClient, username: String, password: String, twoFactor: (method: String, code: String)? = nil) async throws -> String? {
        let form = ZammadClient.SignIn(username: username.trimmingCharacters(in: .whitespaces), password: password,
                                       fingerprint: Self.fingerprint, twoFactorMethod: twoFactor?.method,
                                       twoFactorPayload: twoFactor?.code.trimmingCharacters(in: .whitespaces))
        if let method = try await client.signIn(form) { return method }
        try await finish(client)
        return nil
    }

    /// Loads what the app needs and keeps the session for the next start.
    func finish(_ client: ZammadClient) async throws {
        try await connect(client)
        guard case .session(let web) = client.credential else { return }
        let server = client.baseURL.absoluteString
        UserDefaults.standard.set(server, forKey: Self.serverKey)
        if let data = try? JSONEncoder().encode(web.cookies.map(StoredCookie.init)) { Keychain.save(data, account: server) }
    }

    func connect(_ client: ZammadClient) async throws {
        async let me = client.me()
        async let states = client.states()
        async let priorities = client.priorities()
        async let overviews = client.overviews()
        (self.me, self.states, self.priorities, self.overviews) = try await (me, states.filter(\.active), priorities.filter(\.active), overviews)
        self.client = client
    }

    func loadAgents() async {
        guard agents.isEmpty, let users = try? await client?.users() else { return }
        agents = users
    }

    func reloadOverviews() async {
        if let overviews = try? await client?.overviews() { self.overviews = overviews }
    }

    func signOut() {
        guard let client else { return }
        Keychain.delete(account: client.baseURL.absoluteString)
        Task { await client.signOut() }
        self.client = nil
        me = nil
        overviews = []
        agents = []
    }
}
