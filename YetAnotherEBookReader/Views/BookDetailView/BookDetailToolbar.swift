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
                    Menu {
                        ForEach(viewModel.formatStates) { state in
                            if let format = state.format {
                                Section(header: Text(state.id)) {
                                    BookFormatActions(state: state,
                                        cache: { viewModel.cacheFormat(book: book, format: format) },
                                        clear: { viewModel.clearingFormat = format },
                                        preview: {
                                            if let info = book.formats[state.id] {
                                                _ = viewModel.previewAction(book: book, format: format, formatInfo: info)
                                            }
                                        },
                                        pauseOrResume: {
                                            if state.download?.isDownloading == true { viewModel.pauseDownload(book: book, format: format) }
                                            else { viewModel.resumeDownload(book: book, format: format) }
                                        },
                                        cancel: { viewModel.cancelDownload(book: book, format: format) })
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Files and Formats")
                    .accessibilityIdentifier("book-detail.files")
                    .disabled(viewModel.formatStates.allSatisfy { !$0.isTransferring && !$0.canDownload && !$0.canClear && !$0.canPreview })

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
