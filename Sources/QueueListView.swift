import SwiftUI

/// First screen after sign-in: pick the queue (Zammad group) whose tickets to open.
struct QueueListView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Queue?

    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: Queue.all) { Label("All Queues", systemImage: "tray.2") }
            if !model.groups.isEmpty {
                Section("Queues") {
                    ForEach(model.groups) { group in
                        NavigationLink(value: Queue.group(group)) { Label(group.title, systemImage: "tray") }
                    }
                }
            }
        }
        .navigationTitle("Queues")
        .refreshable { await model.reloadGroups() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if let me = model.me { Text(me.displayName) }
                    Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { model.signOut() }
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
        }
    }
}
