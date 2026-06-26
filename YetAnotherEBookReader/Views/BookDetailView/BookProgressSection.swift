//
//  BookProgressSection.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookProgressSection: View {
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool

    var body: some View {
        HStack {
            Image(systemName: "text.book.closed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 24, alignment: .center)
            
            Button(action:{
                viewModel.prepareReadingPositionHistory(book: book)
                viewModel.readingPositionHistoryViewPresenting = true
            }) {
                if let summary = viewModel.getReadingProgressSummary(for: book) {
                    switch summary {
                    case .goodreadsReadDate(let dateString):
                        Image(systemName: "arrow.down.to.line")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text(dateString)
                    case .goodreadsProgress(let progressString):
                        Image(systemName: "hourglass")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text("\(progressString)%")
                    case .localProgress(let percent, let device):
                        Image(systemName: "book.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                        Text(String(format: "%.1f%%", percent))
                        Text("on")
                        Text(device)
                    }
                } else {
                    Text("No Reading History")
                }
            }.disabled(!viewModel.hasReadingHistory(for: book))
        }.sheet(isPresented: $viewModel.readingPositionHistoryViewPresenting, onDismiss: {
            viewModel.readingPositionHistoryViewPresenting = false
        }, content: {
            NavigationView {
                ReadingPositionHistoryView(presenting: $viewModel.readingPositionHistoryViewPresenting, library: book.library, bookId: book.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction, content: {
                            Button(action: {
                                viewModel.readingPositionHistoryViewPresenting = false
                            }) {
                                Image(systemName: "xmark")
                            }
                        })
                    }
            }
        })
    }
}
