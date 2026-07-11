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
    
    @StateObject private var _viewModel = BookDetailViewModel()
    
    var body: some View {
        ScrollView {
            if let calibreBook = _viewModel.calibreBook {
                Text(calibreBook.title)
                    .accessibilityIdentifier("book-detail.title")
                BookDetailContentView(viewModel: _viewModel, book: calibreBook, isCompat: sizeClass == .compact)
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    .navigationTitle(Text(calibreBook.title))
                    .toolbar {
                        BookDetailToolbar(viewModel: _viewModel, book: calibreBook)
                    }
                    .alert(item: $_viewModel.alertItem) { item in
                        return Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
                    }
            } else {
                Text("Loading book details...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .onAppear() {
            _viewModel.targetWorkspaceID = readerWorkspaceID
            _viewModel.setup(bookId: bookId)
            if let calibreBook = _viewModel.calibreBook {
                _viewModel.fetchMetadata(book: calibreBook)
            }
        }
        .accessibilityIdentifier("screen.book-detail")
    }
}

extension BookDetailView {
    enum Mode: String, CaseIterable, Identifiable {
        case SHELF
        case LIBRARY
        
        var id: String { self.rawValue }
    }
}
