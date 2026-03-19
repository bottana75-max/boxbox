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
    static let f1Background = Color(red: 21/255, green: 21/255, blue: 23/255)
    static let f1CardBackground = Color(red: 32/255, green: 32/255, blue: 35/255)
    static let f1SecondaryBackground = Color(red: 46/255, green: 46/255, blue: 50/255)
    static let f1Subtle = Color(red: 58/255, green: 58/255, blue: 62/255)
}

#Preview {
    ContentView()
}
