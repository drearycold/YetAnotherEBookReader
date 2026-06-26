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
            if viewModel.updatingMetadataStatus == "Success" {
                HStack {
                    metadataIcon(systemName: "checkmark.shield")
                    Text("In Sync with Server")
                }
            } else if viewModel.updatingMetadataStatus == "Local File" {
                HStack {
                    metadataIcon(systemName: "doc")
                    Text("Local File")
                }
            } else if viewModel.updatingMetadataStatus == "Deleted" {
                HStack {
                    metadataIcon(systemName: "xmark.shield")
                    Text("Been Deleted on Server")
                }
            } else if viewModel.updatingMetadataStatus == "Updating" {
                HStack {
                    metadataIcon(systemName: "arrow.clockwise")
                    Text("Syncing with Server")
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action:{
                        alertItem = AlertItem(id: "Sync Error", msg: viewModel.updatingMetadataStatus)
                    }) {
                        HStack {
                            metadataIcon(systemName: "exclamationmark.shield")
                            Text("Sync Error Encounted")
                        }
                    }
                }
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
