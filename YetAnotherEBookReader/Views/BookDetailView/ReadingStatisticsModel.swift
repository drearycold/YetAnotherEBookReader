import SwiftUI

#if canImport(SwiftUICharts)
import SwiftUICharts
#endif

/// Shared statistics presentation and observation for a supplied, already resolved scope.
@MainActor
final class ReadingStatisticsModel: ObservableObject {
    static let previousDays = 7
    static let title = "Today and Previous \(previousDays) Days"

    @Published private(set) var state = ReadingLoadState.loading
    @Published private(set) var snapshot: ReadingStatistics?
    private(set) var dayLabels = [String]()
    #if canImport(SwiftUICharts)
    private(set) var barChartData: BarChartData?
    #endif

    private let repository: ReadingHistoryRepository
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var scope: ReadingHistoryScope?
    private var observedWindow: ReadingStatisticsWindow?
    private var observer: Task<Void, Never>?
    private var load: Task<Void, Never>?
    private var isVisible = false

    init(repository: ReadingHistoryRepository, now: @escaping () -> Date, calendar: @escaping () -> Calendar) {
        self.repository = repository
        self.now = now
        self.calendar = calendar
    }

    deinit {
        observer?.cancel()
        load?.cancel()
    }

    var minutes: [Double] { snapshot?.minutesByDay ?? [] }
    /// Keep loaded rows and the chart in place while the same scope refreshes.
    var presentationState: ReadingLoadState {
        state == .loading && snapshot != nil ? .ready : state
    }
    var hasReading: Bool { minutes.contains { $0 > 0 } }
    var todayMinutes: Int { Int(minutes.last ?? 0) }
    var averageMinutes: Int { Int(snapshot?.previousDayAverage ?? 0) }
    var maximumMinutes: Int { Int(snapshot?.previousDayMaximum ?? 0) }
    var summaryText: String {
        "Today \(todayMinutes) min · Previous \(Self.previousDays) days: avg \(averageMinutes), max \(maximumMinutes) min/day"
    }

    func window() -> ReadingStatisticsWindow {
        ReadingStatisticsWindow(now: now(), calendar: calendar(), previousDays: Self.previousDays)
    }

    func start(scope next: ReadingHistoryScope) {
        guard next != scope || !isVisible else { return }
        if next != scope {
            snapshot = nil
            state = .loading
        }
        scope = next
        isVisible = true
        observe(window: window())
    }

    func stop() {
        isVisible = false
        observer?.cancel()
        observer = nil
        load?.cancel()
    }

    func refresh() {
        guard isVisible else { return }
        refresh(window: window())
    }

    private func observe(window: ReadingStatisticsWindow) {
        guard let scope else { return }
        observer?.cancel()
        load?.cancel()
        observedWindow = window
        let changes = repository.changes(in: scope, for: .statistics(since: window.sessionStartRange.lowerBound))
        observer = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled, let self else { return }
                self.refresh(window: self.window())
            }
        }
    }

    private func refresh(window: ReadingStatisticsWindow) {
        guard let scope else { return }
        if observedWindow?.calendar != window.calendar
            || observedWindow?.sessionStartRange.lowerBound != window.sessionStartRange.lowerBound {
            observe(window: window)
            return
        }
        load?.cancel()
        state = .loading
        let repository = repository
        load = Task { [weak self] in
            do {
                let result = try await repository.statistics(in: scope, window: window)
                guard !Task.isCancelled, let self else { return }
                self.dayLabels = window.dayLabels
                #if canImport(SwiftUICharts)
                self.barChartData = self.makeChart(result)
                #endif
                self.snapshot = result
                self.state = .ready
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed
            }
        }
    }

    #if canImport(SwiftUICharts)
    private func makeChart(_ result: ReadingStatistics) -> BarChartData {
        let colour = ColourStyle(colour: .accentColor)
        return BarChartData(
            dataSets: BarDataSet(
                dataPoints: result.minutesByDay.enumerated().map { index, minutes in
                    BarChartDataPoint(value: minutes, xAxisLabel: dayLabels[index],
                                      description: "\(Int(minutes)) min", colour: colour)
                }, legendTitle: "Minutes"
            ),
            metadata: ChartMetadata(title: Self.title, subtitle: "Minutes"),
            barStyle: BarStyle(barWidth: 0.6, colour: colour),
            chartStyle: BarChartStyle(
                xAxisLabelFont: .caption2, xAxisLabelColour: .secondary,
                yAxisGridStyle: GridStyle(numberOfLines: 3, lineColour: Color(.gray).opacity(0.2), dash: [4]),
                yAxisLabelFont: .caption2, yAxisLabelColour: .secondary,
                yAxisNumberOfLabels: 3, baseline: .zero
            )
        )
    }
    #endif
}
