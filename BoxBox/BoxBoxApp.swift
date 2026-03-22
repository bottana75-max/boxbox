import SwiftUI

@main
struct BoxBoxApp: App {
    @State private var selectedTab: AppTab = .home

    var body: some Scene {
        WindowGroup {
            ContentView(selectedTab: $selectedTab)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "boxbox" else { return }
                    switch url.host {
                    case "schedule":
                        selectedTab = .schedule
                    case "standings":
                        selectedTab = .standings
                    default:
                        break
                    }
                }
        }
    }
}
