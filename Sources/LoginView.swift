import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("server") private var server = ""
    @AppStorage("username") private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var twoFactorMethod: String?
    @State private var prepared: (client: ZammadClient, info: ZammadClient.ServerInfo)?
    @State private var showMicrosoft = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let prepared { credentials(prepared) } else { serverStep }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("TicketMaster")
            .onSubmit { Task { await primaryAction() } }
            .sheet(isPresented: $showMicrosoft) {
                if let prepared, case .session(let web) = prepared.client.credential {
                    NavigationStack {
                        MicrosoftSignInView(client: prepared.client, web: web, fingerprint: AppModel.fingerprint) {
                            showMicrosoft = false
                            Task { await run { try await model.finish(prepared.client) } }
                        }
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("Microsoft")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { showMicrosoft = false } }
                        }
                    }
                }
            }
        }
    }

    private var serverStep: some View {
        Section {
            TextField("helpdesk.example.com", text: $server)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            actionButton("Continue", disabled: server.isEmpty)
        } header: {
            Text("Zammad Server")
        } footer: {
            Text("The address you use to open Zammad in the browser.")
        }
    }

    @ViewBuilder private func credentials(_ prepared: (client: ZammadClient, info: ZammadClient.ServerInfo)) -> some View {
        Section {
            LabeledContent("Server", value: prepared.client.baseURL.host() ?? "")
            Button("Change Server") { reset() }
        }
        if prepared.info.microsoft {
            Section {
                Button {
                    error = nil
                    showMicrosoft = true
                } label: {
                    Label("Sign in with Microsoft", systemImage: "person.badge.key")
                }
                .disabled(busy)
            }
        }
        Section {
            TextField("Username or Email", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(twoFactorMethod != nil)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .disabled(twoFactorMethod != nil)
            if let twoFactorMethod {
                TextField(twoFactorMethod == "recovery_codes" ? "Recovery Code" : "Code from Authenticator App", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(twoFactorMethod == "recovery_codes" ? .asciiCapable : .numberPad)
            }
            actionButton("Sign In", disabled: username.isEmpty || password.isEmpty || (twoFactorMethod != nil && code.isEmpty))
        } header: {
            Text(prepared.info.microsoft ? "Or with Username and Password" : "Username and Password")
        } footer: {
            Text("Your password is not stored. The app stays signed in until you sign out.")
        }
    }

    private func actionButton(_ title: LocalizedStringKey, disabled: Bool) -> some View {
        Button {
            Task { await primaryAction() }
        } label: {
            HStack {
                Text(title)
                Spacer()
                if busy { ProgressView() }
            }
        }
        .disabled(busy || disabled)
    }

    private func reset() {
        prepared = nil
        twoFactorMethod = nil
        code = ""
        error = nil
    }

    private func primaryAction() async {
        guard let prepared else {
            await run { prepared = try await model.prepare(server: server) }
            return
        }
        await run {
            let twoFactor = twoFactorMethod.map { (method: $0, code: code) }
            twoFactorMethod = try await model.signIn(prepared.client, username: username, password: password, twoFactor: twoFactor)
            code = ""
            if twoFactorMethod == nil { password = "" }
        }
    }

    private func run(_ work: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await work()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
