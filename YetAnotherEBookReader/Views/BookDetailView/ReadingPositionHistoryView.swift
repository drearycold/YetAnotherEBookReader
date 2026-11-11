//
//  ReadingPositionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/2.
//

import SwiftUI


/// A single book's history. Reader-opening destinations are pushed above the tabs.
struct ReadingPositionHistoryView: View {
    @Environment(\.readerWorkspaceID) var readerWorkspaceID
    @StateObject private var viewModel: ReadingPositionHistoryViewModel

    init(viewModel: @autoclosure @escaping () -> ReadingPositionHistoryViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            ReadingStatisticsSection(model: viewModel.statistics)
            positionSections
            sessionsSection

            #if DEBUG
            debugSection
            #endif
        }
        .listStyle(.insetGrouped)
        .background(detailLink)
        .navigationTitle("Reading History")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $viewModel.alertItem) { item in
            Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .modifier(ReadingClockUpdates(action: viewModel.clockDidChange))
        .accessibilityIdentifier("screen.reading-history")
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
            if viewModel.isLoadingSessions && viewModel.sessionRows.isEmpty {
                ProgressView()
            } else if viewModel.sessionState == .failed {
                Text("Unable to load local sessions").foregroundColor(.secondary)
                Button("Retry", action: viewModel.retrySessions)
                    .accessibilityIdentifier("reading-history.retry")
            } else if viewModel.sessionRows.isEmpty {
                Text("No sessions on this device")
                    .foregroundColor(.secondary)
            }
            ForEach(viewModel.sessionRows) { row in
                Button(action: {
                    viewModel.showDetail(for: row)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.chapter)
                                .lineLimit(2)
                            Text("\(row.durationText) · \(row.dateText)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        detailChevron
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this session’s saved position")
                .accessibilityIdentifier("reading-history.session")
            }
            if viewModel.hasMoreSessions {
                Button("Load More Sessions", action: viewModel.loadMoreSessions)
                    .disabled(viewModel.isLoadingSessions)
                    .accessibilityIdentifier("reading-history.load-more")
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            if viewModel.hasTestUpdate {
                Button("Update Test History", action: viewModel.updateTestHistory)
                    .accessibilityIdentifier("reading-history.test-update")
            }
            DisclosureGroup("Debug") {
                Text("BookId: \(viewModel.bookId)")
                Text("Library: \(viewModel.library.id)")
                Text("Minutes: \(viewModel.statistics.minutes.map { String(format: "%.1f", $0) }.joined(separator: ", "))")
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
                    detailChevron
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
    
    private var detailChevron: some View {
        Image(systemName: "chevron.forward")
            .font(.caption.weight(.semibold))
            .foregroundColor(Color(uiColor: .tertiaryLabel))
            .accessibilityHidden(true)
    }

    private var detailLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { viewModel.isDetailActive },
                set: { if !$0 { viewModel.dismissDetail() } }
            )
        ) {
            if let detail = viewModel.displayedDetail {
                ReadingPositionDetailView(viewModel: detail).id(detail.id)
            }
        } label: {
            EmptyView()
        }
        .hidden()
    }

}

struct ReadingPositionHistoryView_Previews: PreviewProvider {
    static private var container = AppContainer(mock: true)

    static var previews: some View {
        if let book = container.bookManager.booksInShelf.values.first {
            NavigationView {
                ReadingPositionHistoryView(viewModel: ReadingPositionHistoryViewModel(
                    container: container, book: book))
            }
            .navigationViewStyle(.stack)
            .environment(\.appContainer, container)
        }
    }
}
