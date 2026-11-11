import SwiftUI
import Combine
import UIKit
#if canImport(SwiftUICharts)
import SwiftUICharts
#endif

struct ReadingStatisticsSection: View {
    @ObservedObject var model: ReadingStatisticsModel
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Section {
            switch model.presentationState {
            case .loading:
                ProgressView().accessibilityIdentifier("reading-statistics.loading")
            case .failed:
                Text("Unable to load reading statistics")
                    .foregroundColor(.secondary)
                Button("Retry", action: model.refresh)
                    .accessibilityIdentifier("reading-statistics.retry")
            case .ready:
                if model.hasReading {
                    if textSize.isAccessibilitySize {
                        ForEach(model.minutes.indices, id: \.self) { index in
                            HStack {
                                Text(model.dayLabels[index])
                                Spacer()
                                Text("\(Int(model.minutes[index])) min")
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("reading-statistics.day")
                        }
                    } else {
                        #if canImport(SwiftUICharts)
                        if let data = model.barChartData {
                            BarChart(chartData: data)
                                .xAxisLabels(chartData: data)
                                .yAxisLabels(chartData: data)
                                .yAxisGrid(chartData: data)
                                .frame(height: 140)
                                .padding(.vertical, 8)
                        }
                        #endif
                    }
                } else {
                    Text("No reading today or in the previous \(ReadingStatisticsModel.previousDays) days")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text(ReadingStatisticsModel.title)
        } footer: {
            if model.presentationState == .ready && model.hasReading {
                Text(model.summaryText)
            }
        }
    }
}

struct ReadingClockUpdates: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            Publishers.MergeMany([
                UIApplication.willEnterForegroundNotification,
                UIApplication.significantTimeChangeNotification,
                .NSCalendarDayChanged,
                .NSSystemTimeZoneDidChange,
                NSLocale.currentLocaleDidChangeNotification
            ].map { NotificationCenter.default.publisher(for: $0) })
            .receive(on: RunLoop.main)
        ) { _ in action() }
    }
}
