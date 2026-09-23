import SwiftUI

struct ConsoleView: View {
    @ObservedObject var store: ConsoleStore

    var body: some View {
        ZStack {
            Color(hex: 0x0F111A).ignoresSafeArea()
            NavigationSplitView {
                List {
                    Label("Droid", systemImage: "cpu")
                    Label("Apple", systemImage: "iphone")
                    Label("Sites", systemImage: "globe")
                    Label("Jobs", systemImage: "clock")
                    Label("Notify", systemImage: "bell")
                }
                .navigationSplitViewColumnWidth(180)
            } detail: {
                DroidDashboardView(store: store)
            }
            .navigationTitle(L10n.string("droid.header.title"))
        }
        .background(Color(hex: 0x0F111A))
        .preferredColorScheme(.dark)
    }
}
