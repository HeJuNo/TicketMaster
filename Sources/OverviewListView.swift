import SwiftUI

/// First screen after sign-in: the overviews of the Zammad web app, with their ticket counts.
struct OverviewListView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Overview?

    var body: some View {
        List(model.overviews.sorted { ($0.prio ?? 0) < ($1.prio ?? 0) }, selection: $selection) { overview in
            NavigationLink(value: overview) {
                HStack {
                    Label(overview.name, systemImage: "tray")
                    Spacer()
                    if let count = overview.count {
                        Text(count, format: .number).font(.subheadline.weight(.medium)).monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(count == 0 ? Color.clear : Color.accentColor.opacity(0.15), in: .capsule)
                            .foregroundStyle(count == 0 ? .secondary : .primary)
                    }
                }
            }
        }
        .overlay {
            if model.overviews.isEmpty {
                ContentUnavailableView("No Overviews", systemImage: "tray", description: Text("Your Zammad account has no overviews. Pull down to try again."))
            }
        }
        .navigationTitle("Overviews")
        .refreshable { await model.reloadOverviews() }
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
