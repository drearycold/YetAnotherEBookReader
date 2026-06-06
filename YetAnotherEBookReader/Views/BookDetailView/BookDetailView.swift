//
//  BookView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import Foundation
import OSLog
import SwiftUI
import RealmSwift
//import struct Kingfisher.KFImage
import KingfisherSwiftUI

struct BookDetailView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.openURL) var openURL
    
    @ObservedRealmObject var book: CalibreBookRealm
    
    @ObservedResults(BookDeviceReadingPositionRealm.self, configuration: ModelData.shared?.realmConf) var readingPositions
    
    var viewMode: Mode
    
    @StateObject private var previewViewModel = BookPreviewViewModel()
    
    var defaultLog = Logger()
    

    @State private var presentingReadingSheet = false {
        willSet { if newValue { modelData.presentingStack.append($presentingReadingSheet) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var presentingPreviewSheet = false {
        willSet { if newValue { modelData.presentingStack.append($presentingPreviewSheet) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var activityListViewPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($activityListViewPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }

    @State private var readingPositionHistoryViewPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($readingPositionHistoryViewPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @StateObject private var _viewModel = BookDetailViewModel()
    
    var body: some View {
        
        ScrollView {
            Text(book.title)
            if let calibreBook = modelData.convert(bookRealm: book) {
                viewContent(book: calibreBook, isCompat: sizeClass == .compact)
                    .onAppear() {
                        _viewModel.setup(modelData: modelData, book: book, calibreBook: calibreBook)
                        _viewModel.fetchMetadata(book: calibreBook)
                    }
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    .navigationTitle(Text(book.title))
                    .toolbar {
                        toolbarContent(book: calibreBook)
                    }
                    .alert(item: $_viewModel.alertItem) { item in
                        return Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
                    }
            } else {
                EmptyView()
            }
        }
    }
    
    @ViewBuilder
    private func viewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .center) {
            
            #if canImport(GoogleMobileAds)
            #if GAD_ENABLED
            Banner()
            #endif
            #endif
            
            if isCompat {
                VStack(alignment: .center, spacing: 16) {
                    BookCoverView(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, presentingReadingSheet: $presentingReadingSheet, alertItem: $_viewModel.alertItem)
                    
                    BookMetadataSection(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, readingPositionHistoryViewPresenting: $readingPositionHistoryViewPresenting)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    
                    BookConnectivitySection(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, activityListViewPresenting: $activityListViewPresenting, alertItem: $_viewModel.alertItem)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    
                    BookFormatList(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, presentingPreviewSheet: $presentingPreviewSheet)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    
                    let countPage = book.library.pluginCountPagesWithDefault
                    if countPage.isEnabled {
                        BookCountPagesCorner(book: book, lastUpdated: book.lastUpdated, countPage: countPage, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 32) {
                    BookCoverView(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, presentingReadingSheet: $presentingReadingSheet, alertItem: $_viewModel.alertItem)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        BookMetadataSection(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, readingPositionHistoryViewPresenting: $readingPositionHistoryViewPresenting)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        
                        BookConnectivitySection(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, activityListViewPresenting: $activityListViewPresenting, alertItem: $_viewModel.alertItem)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        
                        BookFormatList(viewModel: _viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, presentingPreviewSheet: $presentingPreviewSheet)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        
                        let countPage = book.library.pluginCountPagesWithDefault
                        if countPage.isEnabled {
                            BookCountPagesCorner(book: book, lastUpdated: book.lastUpdated, countPage: countPage, isCompat: isCompat)
                                .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        }
                    }
                }
            }
            
            #if canImport(GoogleMobileAds)
            #if GAD_ENABLED
            Banner()
            #endif
            #endif
            
            WebViewUI(
                content: book.comments,
                baseURL: book.commentBaseURL
            )
            .frame(maxWidth: isCompat ? 400 : 600, minHeight: 400, maxHeight: 400, alignment: .center)
            
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent(book: CalibreBook) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                _viewModel.refresh(book: book)
            }) {
                if modelData.updatingMetadata {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                _viewModel.downloadOrClearCache(book: book)
            }) {
                if let download = _viewModel.activeDownloads.filter( {$1.isDownloading && $1.book.id == book.id} ).first {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else if book.inShelf {
                    Image(systemName: "star.slash")
                } else {
                    Image(systemName: "star")
                }
            }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                readingPositionHistoryViewPresenting = true
            }) {
                Image(systemName: "clock")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
        }
    }
    
    func handleBookDeleted() {
//        modelData.libraryInfo.deleteBook(book: book)
        //TODO
        //getMetadata()
    }
    
    func generateCommentWithTOC(comments: String, toc: String) -> String {
        let lines = toc.split(separator: "\n")
        let tocHTML = lines.reduce("<div><b>Table of Content</b><ul>\n") { result, line in
            result.appending("<li>").appending(line).appending("</li>").appending("\n")
        }.appending("</ul></div>\n")
        
        return comments + "\n" + tocHTML
    }
}

extension BookDetailView {
    enum Mode: String, CaseIterable, Identifiable {
        case SHELF
        case LIBRARY
        
        var id: String { self.rawValue }
    }
}
