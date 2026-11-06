//
//  BookDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import Foundation
import OSLog
import SwiftUI
import KingfisherSwiftUI

struct BookDetailView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.openURL) var openURL
    @Environment(\.readerWorkspaceID) var readerWorkspaceID
    
    let bookId: String
    
    var viewMode: Mode
    
    var defaultLog = Logger()
    
    @StateObject private var _viewModel: BookDetailViewModel

    init(bookId: String, viewMode: Mode, container: AppContainer) {
        self.bookId = bookId
        self.viewMode = viewMode
        self.__viewModel = StateObject(wrappedValue: BookDetailViewModel(container: container))
    }
    
    var body: some View {
        ScrollView {
            if let calibreBook = _viewModel.calibreBook, calibreBook.inShelfId == bookId {
                Text(calibreBook.title)
                    .accessibilityIdentifier("book-detail.title")
                BookDetailContentView(viewModel: _viewModel, book: calibreBook, isCompat: sizeClass == .compact)
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    .navigationTitle(Text(calibreBook.title))
                    .toolbar {
                        BookDetailToolbar(viewModel: _viewModel)
                    }
                    .alert(item: $_viewModel.alertItem) { item in
                        return Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
                    }
            } else if _viewModel.pageState == .loading {
                ProgressView("Loading book details...")
                    .padding()
            } else {
                VStack(spacing: 12) {
                    Text("Book Unavailable").font(.headline)
                    Text("This book is no longer available in this library.")
                    Button("Retry") {
                        _viewModel.onAppear(bookId: bookId, targetWorkspaceID: readerWorkspaceID)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .accessibilityIdentifier("book-detail.unavailable")
            }
        }
        .background(readingHistoryLink)
        .onAppear() {
            _viewModel.onAppear(bookId: bookId, targetWorkspaceID: readerWorkspaceID)
        }
        .onChange(of: bookId) { id in
            _viewModel.onAppear(bookId: id, targetWorkspaceID: readerWorkspaceID)
        }
        .onDisappear { _viewModel.onDisappear() }
        .accessibilityIdentifier("screen.book-detail")
    }
    
    /// Reading History is pushed, so a reader opened from it shows above it (the reader workspace is
    /// an overlay in `MainView`, which a sheet would cover). One hidden link drives both entry points:
    /// the progress row and the toolbar's clock.
    private var readingHistoryLink: some View {
        NavigationLink(isActive: $_viewModel.isReadingPositionHistoryActive) {
            if let calibreBook = _viewModel.calibreBook, calibreBook.inShelfId == bookId {
                ReadingPositionHistoryView(library: calibreBook.library, bookId: calibreBook.id)
                    .id(calibreBook.inShelfId)
            }
        } label: {
            EmptyView()
        }
        .hidden()
    }
}

extension BookDetailView {
    enum Mode: String, CaseIterable, Identifiable {
        case SHELF
        case LIBRARY
        
        var id: String { self.rawValue }
    }
}
