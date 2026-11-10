//
//  ActivityList.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//

import SwiftUI

struct ActivityList: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ActivityListViewModel
    let close: (() -> Void)?

    init(viewModel: @autoclosure @escaping () -> ActivityListViewModel, close: (() -> Void)? = nil) {
        self._viewModel = StateObject(wrappedValue: viewModel())
        self.close = close
    }

    var body: some View {
        List {
            if viewModel.page.entries.isEmpty {
                if viewModel.filter.isActive {
                    Text("No activity matches these filters").foregroundColor(.secondary)
                } else {
                    Text("No activity in the last 7 days").foregroundColor(.secondary)
                }
            }
            ForEach(viewModel.page.entries) { entry in
                NavigationLink {
                    ActivityDetailView(viewModel: viewModel.makeDetailViewModel(id: entry.id))
                        .id(entry.id)
                } label: {
                    row(entry)
                }
            }
            if viewModel.page.hasMore {
                Button("Load More", action: viewModel.loadMore)
                    .accessibilityIdentifier("activity-log.load-more")
            }
        }
        .navigationTitle("Activity Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if let close {
                    Button("Close", action: close)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Menu("Task Type") {
                        Picker("Task Type", selection: $viewModel.filter.kind) {
                            Text("All Tasks").tag(nil as ActivityLogKind?)
                            ForEach(ActivityLogKind.allCases, id: \.self) { kind in
                                Text(kind.activityTitle()).tag(Optional(kind))
                            }
                        }
                    }
                    Toggle("Failures Only", isOn: $viewModel.filter.failuresOnly)
                    Button("Clear Filters") { viewModel.filter = ActivityLogFilter() }
                        .disabled(!viewModel.filter.isActive)
                } label: {
                    Label("Filters", systemImage: viewModel.filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("activity-log.filters")
            }
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { if $0 == .active { viewModel.refreshIfVisible() } }
    }

    private func row(_ entry: ActivityLogSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(activityEntity(libraryName: entry.libraryName, bookTitle: entry.bookTitle))
            Text(activityTitle(kind: entry.kind, downloadFormat: entry.downloadFormat, legacyType: entry.legacyType))
            Text(entry.state.displayText)
                .fontWeight(.semibold)
            Text(entry.startDatetime.formatted(date: .numeric, time: .standard))
                .foregroundColor(.secondary)
            if let duration = entry.duration {
                Text(formattedActivityDuration(duration))
                    .foregroundColor(.secondary)
            }
            if let result = entry.resultPreview {
                Text(result)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

struct ActivityDetailView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ActivityDetailViewModel

    init(viewModel: @autoclosure @escaping () -> ActivityDetailViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            if let entry = viewModel.entry {
                sections(entry)
            } else {
                Text("This activity is no longer available.").foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onChange(of: scenePhase) { if $0 == .active { viewModel.refreshIfVisible() } }
    }

    @ViewBuilder
    private func sections(_ entry: ActivityLogSnapshot) -> some View {
        Section("Activity") {
            LabeledActivityValue(title: entry.bookTitle?.isEmpty == false ? "Book" : "Library",
                                 value: activityEntity(libraryName: entry.libraryName, bookTitle: entry.bookTitle))
            LabeledActivityValue(title: "Task", value: activityTitle(kind: entry.kind,
                                 downloadFormat: entry.downloadFormat, legacyType: entry.legacyType))
            LabeledActivityValue(title: "Status", value: entry.statusText)
            LabeledActivityValue(title: "Started", value: entry.startDatetime.formatted(date: .long, time: .complete))
            if let finished = entry.finishDatetime {
                if entry.state == .legacy {
                    LabeledActivityValue(title: "Last Recorded", value: finished.formatted(date: .long, time: .complete))
                } else if entry.state == .finished(.interrupted) {
                    LabeledActivityValue(title: "Marked Interrupted", value: finished.formatted(date: .long, time: .complete))
                } else if case .finished = entry.state {
                    LabeledActivityValue(title: "Finished", value: finished.formatted(date: .long, time: .complete))
                }
            }
            if let duration = entry.state.elapsed(from: entry.startDatetime, to: entry.finishDatetime) {
                LabeledActivityValue(title: "Duration", value: formattedActivityDuration(duration))
            }
            if let code = entry.result.httpStatusCode {
                LabeledActivityValue(title: "HTTP Status", value: String(code))
            }
            if let category = entry.result.errorCategory {
                LabeledActivityValue(title: "Error Category", value: category.displayText)
            }
            if let detail = entry.legacyResult ?? entry.result.detail {
                LabeledActivityValue(title: "Result", value: detail)
            }
        }
        if !entry.progressChanges.isEmpty {
            Section("Progress") {
                ForEach(entry.progressChanges, id: \.revision) { change in
                    LabeledActivityValue(title: change.progress == .paused ? "Paused" : "Resumed",
                                         value: change.date.formatted(date: .long, time: .complete))
                }
            }
        }
        if entry.result.requests.first?.request != entry.request {
            Section(entry.result.requests.isEmpty ? "Request" : "Initial Request") {
                requestValues(entry.request)
            }
        }
        ForEach(entry.result.requests.indices, id: \.self) { index in
            let diagnostic = entry.result.requests[index]
            Section("Request \(index + 1)") {
                requestValues(diagnostic.request)
                if let responseURL = diagnostic.responseURL {
                    LabeledActivityValue(title: "Response URL", value: responseURL)
                }
                if let code = diagnostic.httpStatusCode {
                    LabeledActivityValue(title: "HTTP Status", value: String(code))
                }
                LabeledActivityValue(title: "Duration", value: formattedActivityDuration(diagnostic.duration))
            }
        }
    }

    @ViewBuilder
    private func requestValues(_ request: ActivityLogRequestSnapshot) -> some View {
        LabeledActivityValue(title: "URL", value: request.endpointURL ?? String(localized: "Unknown"))
        LabeledActivityValue(title: "Method", value: request.httpMethod ?? "GET")
        LabeledActivityValue(
            title: "Body",
            value: request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? String(localized: "Empty")
        )
        if !request.headers.isEmpty {
            DisclosureGroup("Headers") {
                ForEach(request.headers.indices, id: \.self) { index in
                    let header = request.headers[index]
                    LabeledActivityValue(title: LocalizedStringKey(header.key), value: header.value)
                }
            }
        }
    }
}

private func activityEntity(libraryName: String?, bookTitle: String?) -> String {
    if let bookTitle, !bookTitle.isEmpty { return bookTitle }
    return libraryName ?? String(localized: "No Library")
}

private func activityTitle(kind: ActivityLogKind?, downloadFormat: String?, legacyType: String?) -> String {
    kind?.activityTitle(downloadFormat: downloadFormat) ?? legacyType ?? String(localized: "Unknown Task")
}

private func formattedActivityDuration(_ duration: TimeInterval) -> String {
    duration.formatted(.number.precision(.fractionLength(0...3))) + " s"
}

private extension ActivityLogKind {
    func activityTitle(downloadFormat: String? = nil) -> String {
        switch self {
        case .bookMetadata: return String(localized: "Get Book Metadata")
        case .batchMetadata: return String(localized: "Get Books Metadata")
        case .bookManifest: return String(localized: "Get Book Manifest")
        case .updateMetadata: return String(localized: "Set Book Metadata")
        case .librarySummary: return String(localized: "Library Summary")
        case .search: return String(localized: "Search")
        case .categories: return String(localized: "Categories")
        case .probe: return String(localized: "Server Check")
        case .readingPosition: return String(localized: "Reading Position")
        case .annotations: return String(localized: "Annotations")
        case .helper: return String(localized: "DSReader Helper")
        case .download:
            if let downloadFormat { return String(localized: "Download \(downloadFormat)") }
            return String(localized: "Download")
        }
    }
}

extension ActivityLogSnapshot {
    var statusText: String { state.displayText }
}

private extension ActivityLogState {
    var displayText: String {
        switch self {
        case .inProgress(.running): return String(localized: "Running")
        case .inProgress(.paused): return String(localized: "Paused")
        case .finished(.succeeded): return String(localized: "Succeeded")
        case .finished(.failed): return String(localized: "Failed")
        case .finished(.cancelled): return String(localized: "Cancelled")
        case .finished(.interrupted): return String(localized: "Interrupted")
        case .legacy: return String(localized: "Legacy Entry")
        }
    }
}

private extension ActivityLogErrorCategory {
    var displayText: String {
        switch self {
        case .invalidRequest: return String(localized: "Invalid Request")
        case .transport: return String(localized: "Transport")
        case .http: return "HTTP"
        case .authentication: return String(localized: "Authentication")
        case .decoding: return String(localized: "Decoding")
        case .serverRejected: return String(localized: "Server Rejected Request")
        case .file: return String(localized: "File")
        case .unknown: return String(localized: "Unknown")
        }
    }
}

private struct LabeledActivityValue: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

struct ActivityList_Previews: PreviewProvider {
    static private var container = AppContainer(mock: true)
    
    static var previews: some View {
        NavigationView {
            ActivityList(
                viewModel: ActivityListViewModel(repository: container.activityLogRepository)
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
