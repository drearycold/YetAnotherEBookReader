//
//  BookDetailToolbar.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookDetailToolbar: ToolbarContent {
    let viewModel: BookDetailViewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            BookDetailToolbarControls(viewModel: viewModel, refreshOnly: true)
        }
        // One item per placement: iOS 15 otherwise hides the history action.
        ToolbarItem(placement: .navigationBarTrailing) {
            BookDetailToolbarControls(viewModel: viewModel, refreshOnly: false)
        }
    }
}

/// iOS 15 retains ToolbarContent's initial values. A hosted View observes changes and reads the
/// current book at the point of use, including after a refresh, cache change or book switch.
private struct BookDetailToolbarControls: View {
    @ObservedObject var viewModel: BookDetailViewModel
    let refreshOnly: Bool

    var body: some View {
        if let book = viewModel.calibreBook {
            if refreshOnly {
                Button {
                    if viewModel.updatingMetadata { viewModel.cancelRefresh() }
                    else { viewModel.refresh(book: book) }
                } label: {
                    Image(systemName: viewModel.updatingMetadata ? "xmark" : "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel(viewModel.updatingMetadata ? "Cancel Refresh" : "Refresh Book Details")
                .accessibilityIdentifier("book-detail.refresh")
            } else {
                HStack(spacing: 16) {
                    Button {
                        viewModel.downloadOrClearCache(book: book)
                    } label: {
                        if viewModel.hasActiveDownload(book) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: book.inShelf ? "star.slash" : "star")
                        }
                    }
                    .accessibilityLabel(book.inShelf ? "Clear Downloaded Files" : "Download Only")

                    Button {
                        viewModel.showReadingPositionHistory(book: book)
                    } label: {
                        Image(systemName: "clock")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    }
                    .accessibilityLabel("Reading History")
                    .accessibilityIdentifier("book-detail.history")
                }
            }
        }
    }
}
