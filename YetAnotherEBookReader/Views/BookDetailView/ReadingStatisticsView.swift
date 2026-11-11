import SwiftUI

struct ReadingStatisticsView: View {
    @StateObject private var viewModel: ReadingStatisticsViewModel
    @ObservedObject private var statistics: ReadingStatisticsModel
    @Environment(\.dynamicTypeSize) private var textSize

    init(viewModel: ReadingStatisticsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        statistics = viewModel.statistics
    }

    var body: some View {
        List {
            ReadingStatisticsSection(model: statistics)
            if statistics.presentationState == .ready {
                Section(header: Text("Books")) {
                    if viewModel.booksHistoryItems.isEmpty {
                        Text("No books read today or in the previous \(ReadingStatisticsModel.previousDays) days")
                            .foregroundColor(.secondary)
                    }
                    ForEach(viewModel.booksHistoryItems) { item in
                        Button {
                            viewModel.showHistory(for: item.id)
                        } label: {
                            HStack {
                                if textSize.isAccessibilitySize {
                                    VStack(alignment: .leading) {
                                        Text(item.book.title)
                                        minutesLabel(item)
                                    }
                                    Spacer()
                                } else {
                                    Text(item.book.title).lineLimit(2)
                                    Spacer()
                                    minutesLabel(item)
                                }
                                Image(systemName: "chevron.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reading-statistics.book")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reading Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .background(historyLink)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .modifier(ReadingClockUpdates(action: viewModel.clockDidChange))
        .alert(item: $viewModel.alertItem) { item in
            Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .accessibilityIdentifier("screen.reading-statistics")
    }

    private func minutesLabel(_ item: BookHistoryItem) -> some View {
        Text("\(item.minutesText) min")
            .font(.subheadline.monospacedDigit())
            .foregroundColor(.secondary)
    }

    private var historyLink: some View {
        NavigationLink(isActive: $viewModel.isHistoryActive) {
            if let history = viewModel.displayedHistory {
                ReadingPositionHistoryView(viewModel: history).id(history.id)
            }
        } label: {
            EmptyView()
        }
        .hidden()
    }
}
