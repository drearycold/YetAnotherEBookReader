//
//  ReadingPositionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/2.
//

import SwiftUI

#if canImport(SwiftUICharts)
import SwiftUICharts
#endif

/// A book's reading history (`library` and `bookId` given), or reading statistics for every book on
/// the shelf. Pushed, never presented in a sheet: Continue Reading opens the reader workspace, an
/// overlay in `MainView` that a sheet would cover.
struct ReadingPositionHistoryView: View {
    @Environment(\.readerWorkspaceID) var readerWorkspaceID
    @StateObject private var viewModel: ReadingPositionHistoryViewModel

    init(library: CalibreLibrary?, bookId: Int32?) {
        self._viewModel = StateObject(wrappedValue: ReadingPositionHistoryViewModel(library: library, bookId: bookId))
    }

    var body: some View {
        List {
            statisticsSection

            if viewModel.isBookMode {
                positionSections
                sessionsSection
            } else {
                booksSection
            }

            #if DEBUG
            debugSection
            #endif
        }
        .listStyle(.insetGrouped)
        .background(detailLink)
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $viewModel.alertItem) { item in
            Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .onAppear {
            viewModel.loadData()
            viewModel.observeChanges()
        }
        .accessibilityIdentifier("screen.reading-history")
    }

    private var statisticsSection: some View {
        Section {
            if viewModel.hasRecentReading {
                #if canImport(SwiftUICharts)
                if let data = viewModel.barChartData {
                    BarChart(chartData: data)
                        .xAxisLabels(chartData: data)
                        .yAxisLabels(chartData: data)
                        .yAxisGrid(chartData: data)
                        .frame(height: 140)
                        .padding(.vertical, 8)
                }
                #endif
            } else {
                Text("No reading in the last \(ReadingPositionHistoryViewModel.limitDays) days")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Last \(ReadingPositionHistoryViewModel.limitDays) Days")
        } footer: {
            if viewModel.hasRecentReading {
                Text(viewModel.summaryText)
            }
        }
    }

    @ViewBuilder
    private var positionSections: some View {
        if viewModel.deviceSections.isEmpty {
            Section(header: Text("Positions")) {
                Text("No saved positions yet")
                    .foregroundColor(.secondary)
            }
        } else {
            ForEach(viewModel.deviceSections) { section in
                Section {
                    ForEach(section.rows) { row in
                        positionRow(row)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("On \(section.deviceName)")
                        if section.isThisDevice {
                            Text("This Device")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundColor(.white)
                                .background(Capsule().fill(Color.accentColor))
                        }
                    }
                }
            }
        }
    }

    private var sessionsSection: some View {
        Section(header: Text("Local Sessions")) {
            if viewModel.sessionRows.isEmpty {
                Text("No sessions on this device")
                    .foregroundColor(.secondary)
            }
            ForEach(viewModel.sessionRows) { row in
                Button(action: {
                    viewModel.showDetail(for: row.endPosition)
                }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.chapter)
                            .lineLimit(2)
                        Text("\(row.durationText) · \(row.dateText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var booksSection: some View {
        Section(header: Text("Books")) {
            if viewModel.booksHistoryItems.isEmpty {
                Text("No books read in the last \(ReadingPositionHistoryViewModel.limitDays) days")
                    .foregroundColor(.secondary)
            }
            ForEach(viewModel.booksHistoryItems) { item in
                NavigationLink(
                    destination: LazyView(ReadingPositionHistoryView(library: item.book.library, bookId: item.book.id))
                ) {
                    HStack {
                        Text(item.book.title)
                            .lineLimit(2)
                        Spacer()
                        Text("\(item.minutesText) min")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            DisclosureGroup("Debug") {
                Text("BookId: \(viewModel.bookId ?? -1)")
                Text("Library: \(viewModel.library?.id ?? "NO LIB")")
                Text("Minutes: \(viewModel.readingStatistics.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
                ForEach(Array(viewModel.debugReadingPositions.enumerated()), id: \.offset) { _, readingPosition in
                    HStack {
                        Text(readingPosition.id)
                        Text(readingPosition.lastReadChapter)
                        Text("\(readingPosition.lastProgress)")
                    }
                    .font(.caption)
                }
            }
        }
    }
    #endif

    /// The row's info opens its detail and the play button continues reading from it. They are
    /// sibling buttons, plain and borderless, so a List row gives each its own taps; a button inside
    /// a NavigationLink row would push the detail instead.
    private func positionRow(_ row: ReadingHistoryPositionRow) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.showDetail(for: row.position)
            }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .lineLimit(2)
                        if let detail = row.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Text("\(row.relativeTimeText) · \(row.readerName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Text(row.percentText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows this position's details")
            .accessibilityIdentifier("reading-history.position")
            
            Button(action: {
                viewModel.continueReading(row, targetWorkspaceID: readerWorkspaceID)
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(!row.canContinue)
            .accessibilityLabel("Continue Reading")
            .accessibilityIdentifier("reading-history.continue")
        }
    }
    
    /// The single hidden link for a position's detail, in book mode only. Settings mode has a
    /// NavigationLink per book, and iOS 15 pops a programmatic link that shares its view with
    /// another one.
    @ViewBuilder
    private var detailLink: some View {
        if viewModel.isBookMode {
            NavigationLink(
                isActive: Binding(
                    get: { viewModel.detailPosition != nil },
                    set: { isActive in
                        if !isActive {
                            viewModel.dismissDetail()
                        }
                    }
                )
            ) {
                if let position = viewModel.displayedDetailPosition {
                    positionDetail(position)
                        .id(position)
                }
            } label: {
                EmptyView()
            }
            .hidden()
        }
    }
    
    @ViewBuilder
    private func positionDetail(_ position: BookDeviceReadingPosition) -> some View {
        if let listViewModel = viewModel.listViewModel {
            ReadingPositionDetailView(
                viewModel: viewModel.detailViewModel(
                    for: position,
                    listViewModel: listViewModel,
                    targetWorkspaceID: readerWorkspaceID
                )
            )
        } else {
            Text("This book is no longer in the library")
                .foregroundColor(.secondary)
        }
    }
}

struct ReadingPositionHistoryView_Previews: PreviewProvider {
    static private var container = AppContainer(mock: true)

    static var previews: some View {
        if let book = container.bookManager.booksInShelf.values.first {
            NavigationView {
                ReadingPositionHistoryView(library: book.library, bookId: book.id)
            }
            .navigationViewStyle(.stack)
            .environment(\.appContainer, container)
        }
    }
}
