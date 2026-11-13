import Foundation
import Observation

@Observable final class AppModel {
    var client: ZammadClient?
    var me: User?
    var states: [TicketState] = []
    var priorities: [TicketPriority] = []

    private static let serverKey = "server"

    /// Signs in again with the server and token from the last session.
    func restore() async {
        guard client == nil, let server = UserDefaults.standard.string(forKey: Self.serverKey),
              let url = URL(string: server), let token = Keychain.load(account: server) else { return }
        try? await connect(ZammadClient(baseURL: url, token: token))
    }

    func signIn(server: String, token: String) async throws {
        let url = try ZammadClient.serverURL(server)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ZammadError(message: "Enter your access token.") }
        try await connect(ZammadClient(baseURL: url, token: token))
        UserDefaults.standard.set(url.absoluteString, forKey: Self.serverKey)
        Keychain.save(token, account: url.absoluteString)
    }

    func connect(_ client: ZammadClient) async throws {
        async let me = client.me()
        async let states = client.states()
        async let priorities = client.priorities()
        (self.me, self.states, self.priorities) = try await (me, states.filter(\.active), priorities.filter(\.active))
        self.client = client
    }

    func signOut() {
        if let server = client?.baseURL.absoluteString { Keychain.delete(account: server) }
        client = nil
        me = nil
    }
}
