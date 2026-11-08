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
                    ActivityDetailView(obj: entry)
                } label: {
                    row(obj: entry)
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

    @ViewBuilder
    private func row(obj: ActivityLogUIEntry) -> some View {
        VStack {
            HStack {
                Text(obj.bookTitle.isEmpty ? obj.libraryName : obj.bookTitle)
                Spacer()
            }
            HStack {
                Text(obj.type)
                Spacer()
                Text(obj.errMsg)
            }.font(.caption)
            HStack {
                Text(obj.startDateString)
                Spacer()
                Text("->")
                Spacer()
                Text(obj.finishDateString)
            }.font(.caption)
        }
    }
}

struct ActivityDetailView: View {
    let obj: ActivityLogUIEntry
    
    var body: some View {
        List {
            Section("Activity") {
                LabeledActivityValue(title: obj.bookTitle.isEmpty ? "Library" : "Book",
                                     value: obj.bookTitle.isEmpty ? obj.libraryName : obj.bookTitle)
                LabeledActivityValue(title: "Task", value: obj.type)
                LabeledActivityValue(title: "Started", value: obj.startDateLongString)
                LabeledActivityValue(title: "Finished", value: obj.finishDateLongString)
                LabeledActivityValue(title: "Result", value: obj.errMsg)
            }
            Section("Request") {
                LabeledActivityValue(title: "URL", value: obj.endpointURL)
                LabeledActivityValue(title: "Method", value: obj.httpMethod)
                LabeledActivityValue(title: "Body", value: obj.httpBodyString ?? "Empty")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity Details")
        .navigationBarTitleDisplayMode(.inline)
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
