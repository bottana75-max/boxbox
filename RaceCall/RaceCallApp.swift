import SwiftUI

@main
struct RaceCallApp: App {
    @State private var selectedTab: AppTab = .home

    var body: some Scene {
        WindowGroup {
            ContentView(selectedTab: $selectedTab)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "racecall" else { return }
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
