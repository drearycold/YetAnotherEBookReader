//
//  BookDetailToolbar.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookDetailToolbar: ToolbarContent {
    @ObservedObject var viewModel: BookDetailViewModel
    let book: CalibreBook
    
    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                viewModel.refresh(book: book)
            }) {
                if viewModel.updatingMetadata {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        
        // One group: iOS 15 shows only the first of several items sharing a placement, which hid
        // the history button.
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(action: {
                viewModel.downloadOrClearCache(book: book)
            }) {
                if viewModel.hasActiveDownload(book) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else if book.inShelf {
                    Image(systemName: "star.slash")
                } else {
                    Image(systemName: "star")
                }
            }
            .accessibilityLabel(book.inShelf ? "Clear Downloaded Files" : "Download Only")

            Button(action: {
                viewModel.showReadingPositionHistory(book: book)
            }) {
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
