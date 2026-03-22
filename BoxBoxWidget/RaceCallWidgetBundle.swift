import SwiftUI
import WidgetKit

@main
struct RaceCallWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextRaceWidget()
        StandingsWidget()
    }
}
