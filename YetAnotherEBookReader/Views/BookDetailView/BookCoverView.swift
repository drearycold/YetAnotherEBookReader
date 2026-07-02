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
        ZStack {
            KFImage(book.coverURL)
                .placeholder {
                    Text("Loading Cover ...")
                }
                .resizable()
                .scaledToFit()
            Button(action: {
                guard viewModel.activeDownloads.filter({ $1.isActive && $1.book.id == book.id }).isEmpty else { return }
                viewModel.readBook(book: book)
                if book.inShelf {
                    viewModel.presentingReadingSheet = true
                }
            }) {
                if viewModel.activeDownloads.filter({ $1.book.id == book.id && $1.isActive }).isEmpty == false ||
                    book.formats.filter({ $0.value.selected == true && $0.value.cached == false }).isEmpty == false {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                        .scaleEffect(6, anchor: .center)
                } else if book.inShelf,
                          book.formats.allSatisfy({ $1.selected != true || $1.cached }) {
                    Image(systemName: "book")
                        .resizable()
                        .frame(width: 160, height: 160)
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "tray.and.arrow.down")
                        .resizable()
                        .frame(width: 160, height: 160)
                        .foregroundColor(.gray)
                }
            }
            .opacity(0.8)
            .fullScreenCover(isPresented: $viewModel.presentingReadingSheet) {
                if let readerInfo = viewModel.readerInfo {
                    YabrEBookReader(
                        book: book,
                        readerInfo: readerInfo
                    )
                }
            }
        }
        .frame(width: 300, height: 400)
    }
}
