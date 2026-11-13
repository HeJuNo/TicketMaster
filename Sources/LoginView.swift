import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("server") private var server = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("helpdesk.example.com", text: $server)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Zammad Server")
                }
                Section {
                    SecureField("Access Token", text: $token)
                        .textContentType(.password)
                } header: {
                    Text("Access Token")
                } footer: {
                    Text("Create a token in Zammad under Profile > Token Access with the permission “ticket.agent”. It is stored in the keychain on this device.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Sign In")
                            Spacer()
                            if busy { ProgressView() }
                        }
                    }
                    .disabled(busy || server.isEmpty || token.isEmpty)
                }
            }
            .navigationTitle("TicketMaster")
            .onSubmit { Task { await signIn() } }
        }
    }

    private func signIn() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await model.signIn(server: server, token: token)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
