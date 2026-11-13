import SwiftUI

@main
struct TicketMasterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "demo") { try? await model.connect(Demo.client); return }
                    if UserDefaults.standard.bool(forKey: "demoLogin") {  // empty sign-in form against canned answers
                        ["server", "username"].forEach(UserDefaults.standard.removeObject)
                        model.urlSession = FixtureProtocol.session
                        return
                    }
                    #endif
                    await model.restore()
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var overview: Overview?
    @State private var selection: Ticket?

    var body: some View {
        if model.client == nil {
            LoginView()
        } else {
            NavigationSplitView {
                OverviewListView(selection: $overview)
            } content: {
                if let overview {
                    TicketListView(overview: overview, selection: $selection).id(overview)
                } else {
                    ContentUnavailableView("No Overview Selected", systemImage: "tray.2",
                                           description: Text("Choose an overview to see its tickets."))
                }
            } detail: {
                if let selection {
                    TicketDetailView(ticket: selection).id(selection.id)
                } else {
                    ContentUnavailableView("No Ticket Selected", systemImage: "ticket",
                                           description: Text("Choose a ticket from the list."))
                }
            }
            .onChange(of: overview) { selection = nil }
            #if DEBUG
            .task {  // -demoTicket 2: open that ticket right away (screenshots)
                let id = UserDefaults.standard.integer(forKey: "demoTicket")
                if id > 0, let t = try? await model.client?.ticket(id) {
                    overview = model.overviews.first
                    try? await Task.sleep(for: .milliseconds(300))  // let the overview change clear the old selection first
                    selection = t
                }
            }
            #endif
        }
    }
}
