//
//  BookCoverView.swift
//  YetAnotherEBookReader
//

import SwiftUI
import KingfisherSwiftUI

struct BookCoverView: View {
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    
    @Binding var alertItem: AlertItem?

    var body: some View {
        VStack(spacing: 12) {
            KFImage(book.coverURL)
                .placeholder {
                    Text("Loading Cover ...")
                }
                .resizable()
                .scaledToFit()
                .frame(width: 300, height: 300)
                .accessibilityHidden(true)
            Button(action: {
                viewModel.readBook(book: book)
            }) {
                HStack {
                    if viewModel.isWaitingToRead(book) { ProgressView() }
                    Label(viewModel.readActionTitle(for: book),
                          systemImage: viewModel.canRead(book) ? "book" : "tray.and.arrow.down")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isWaitingToRead(book))
            .accessibilityLabel(Text(viewModel.readActionTitle(for: book)))
            .accessibilityIdentifier("book-detail.read")

            if viewModel.isWaitingToRead(book) {
                Button("Cancel Download") { viewModel.cancelReadDownload(book: book) }
                    .accessibilityIdentifier("book-detail.cancel-download")
            } else if !viewModel.canRead(book) {
                Button("Download Only") { viewModel.downloadOnly(book: book) }
                    .disabled(viewModel.hasActiveDownload(book))
                    .accessibilityIdentifier("book-detail.download-only")
            }
        }
        .frame(width: 300)
    }
}
