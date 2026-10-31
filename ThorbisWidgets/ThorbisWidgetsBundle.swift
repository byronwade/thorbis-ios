import SwiftUI
import WidgetKit

@main
struct ThorbisWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayJobsWidget()
        NextStopWidget()
        JobLiveActivityWidget()
        NextStepControl()
        NextJobControl()
    }
}
