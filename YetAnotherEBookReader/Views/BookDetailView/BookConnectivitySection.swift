//
//  BookConnectivitySection.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookConnectivitySection: View {
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool
    
    @Binding var alertItem: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch viewModel.refreshState {
                case .idle:
                    metadataIcon(systemName: "arrow.clockwise")
                    Text("Details Saved on This Device")
                case .refreshing:
                    metadataIcon(systemName: "arrow.clockwise")
                    Text("Syncing with Server")
                case .synced:
                    metadataIcon(systemName: "checkmark.shield")
                    Text("In Sync with Server")
                case .local:
                    metadataIcon(systemName: "doc")
                    Text("Local File")
                case .unavailable:
                    metadataIcon(systemName: "xmark.shield")
                    Text("Unavailable on Server")
                case .failed(let message):
                    metadataIcon(systemName: "exclamationmark.shield")
                    Button("Refresh Failed") {
                        alertItem = AlertItem(id: "Refresh Failed", msg: message)
                    }
                }
            }
            if viewModel.refreshState == .unavailable {
                Text("The server cannot provide this book. Downloaded files remain available to read.")
                    .font(.caption)
            }
            if case .failed = viewModel.refreshState {
                Button("Retry Refresh") { viewModel.refresh(book: book) }
            }
            HStack {
                metadataIcon(systemName: "scroll")
                Button(action: {
                    viewModel.activityListViewPresenting = true
                }) {
                    Text("Activity Logs")
                }.sheet(isPresented: $viewModel.activityListViewPresenting, onDismiss: {
                }, content: {
                    NavigationView {
                        if let container = viewModel.sharedAppContainer {
                            ActivityList(
                                viewModel: ActivityListViewModel(container: container, libraryId: book.library.id, bookId: book.id),
                                presenting: $viewModel.activityListViewPresenting
                            )
                        }
                    }
                })
            }
        }
    }
    
    private func metadataIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 24, alignment: .center)
    }
}
