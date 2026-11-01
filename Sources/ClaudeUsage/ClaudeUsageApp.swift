import SwiftUI

@main
struct ClaudeUsageApp: App {
    @State private var store = UsageStore()
    @AppStorage("menuBarDisplay") private var display: MenuBarDisplay = .session

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(store: store)
        } label: {
            Image(nsImage: MenuBarIcon.image(usage: store.usage, display: display))
        }
        .menuBarExtraStyle(.window)
    }
}
