//
//  ActivityList.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//

import SwiftUI

struct ActivityList: View {
    @StateObject private var viewModel: ActivityListViewModel
    let close: (() -> Void)?

    init(viewModel: @autoclosure @escaping () -> ActivityListViewModel, close: (() -> Void)? = nil) {
        self._viewModel = StateObject(wrappedValue: viewModel())
        self.close = close
    }

    var body: some View {
        List {
            if viewModel.activities.isEmpty {
                Text("No activity in the last 7 days")
                    .foregroundColor(.secondary)
            }
            ForEach(viewModel.activities) { entry in
                NavigationLink {
                    ActivityDetailView(entry: entry)
                } label: {
                    row(entry)
                }
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
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private func row(_ entry: ActivityLogSnapshot) -> some View {
        VStack {
            HStack {
                Text(entry.entityText)
                Spacer()
            }
            HStack {
                Text(entry.kindText)
                Spacer()
                Text(entry.statusText)
            }.font(.caption)
            HStack {
                Text(entry.startDatetime.formatted(date: .numeric, time: .standard))
                Spacer()
                if let finished = entry.finishDatetime {
                    Text("->")
                    Spacer()
                    Text(finished.formatted(date: .numeric, time: .standard))
                }
            }.font(.caption)
        }
    }
}

struct ActivityDetailView: View {
    let entry: ActivityLogSnapshot

    var body: some View {
        List {
            Section("Activity") {
                LabeledActivityValue(title: entry.entityTitle, value: entry.entityText)
                LabeledActivityValue(title: "Task", value: entry.kindText)
                LabeledActivityValue(title: "Status", value: entry.statusText)
                LabeledActivityValue(title: "Started", value: entry.startDatetime.formatted(date: .long, time: .complete))
                if let finished = entry.finishDatetime {
                    LabeledActivityValue(title: "Finished", value: finished.formatted(date: .long, time: .complete))
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
            if entry.result.requests.isEmpty {
                Section("Request") {
                    requestValues(entry.request)
                }
            } else {
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
                        LabeledActivityValue(title: "Duration", value: diagnostic.duration.formatted(.number.precision(.fractionLength(3))) + " s")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func requestValues(_ request: ActivityLogRequestSnapshot) -> some View {
        LabeledActivityValue(title: "URL", value: request.endpointURL ?? String(localized: "Unknown"))
        LabeledActivityValue(title: "Method", value: request.httpMethod ?? "GET")
        LabeledActivityValue(
            title: "Body",
            value: request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? String(localized: "Empty")
        )
    }
}

extension ActivityLogSnapshot {
    fileprivate var entityTitle: LocalizedStringKey {
        bookTitle?.isEmpty == false ? "Book" : "Library"
    }

    fileprivate var entityText: String {
        if let bookTitle, !bookTitle.isEmpty {
            return bookTitle
        }
        return libraryName ?? String(localized: "No Entity")
    }

    fileprivate var kindText: String {
        switch kind {
        case .bookMetadata: return String(localized: "Get Book Metadata")
        case .batchMetadata: return String(localized: "Get Books Metadata")
        case .bookManifest: return String(localized: "Get Book Manifest")
        case .updateMetadata: return String(localized: "Set Book Metadata")
        case .librarySummary: return String(localized: "Library Summary")
        case .search: return String(localized: "Search")
        case .categories: return String(localized: "Categories")
        case .probe: return String(localized: "Server Probe")
        case .readingPosition: return String(localized: "Reading Position")
        case .annotations: return String(localized: "Annotations")
        case .helper: return String(localized: "DSReader Helper")
        case .download:
            if let format = downloadFormat { return String(localized: "Download \(format)") }
            return String(localized: "Download")
        case nil: return legacyType ?? String(localized: "Unknown Type")
        }
    }

    var statusText: String {
        switch state {
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
