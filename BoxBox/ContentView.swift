import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Predict", systemImage: "sparkles") {
                PredictView()
            }
            Tab("Standings", systemImage: "chart.bar.fill") {
                StandingsView()
            }
            Tab("Schedule", systemImage: "calendar") {
                ScheduleView()
            }
            Tab("Drivers", systemImage: "person.3.fill") {
                DriversView()
            }
        }
        .tint(Color.f1Red)
    }
}

extension Color {
    static let f1Red = Color(red: 232/255, green: 0/255, blue: 45/255)
    static let f1Background = Color(red: 26/255, green: 26/255, blue: 26/255)
    static let f1CardBackground = Color(red: 38/255, green: 38/255, blue: 38/255)
    static let f1SecondaryBackground = Color(red: 50/255, green: 50/255, blue: 50/255)
}

#Preview {
    ContentView()
}
