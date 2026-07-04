//
//  BookDetailContentView.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookDetailContentView: View {
    @ObservedObject var viewModel: BookDetailViewModel
    let book: CalibreBook
    let isCompat: Bool
    
    var body: some View {
        VStack(alignment: .center) {
            
            #if canImport(GoogleMobileAds)
            #if GAD_ENABLED
            Banner()
            #endif
            #endif
            
            if isCompat {
                VStack(alignment: .center, spacing: 16) {
                    BookCoverView(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, alertItem: $viewModel.alertItem)
                    
                    BookMetadataSection(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    
                    BookConnectivitySection(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, alertItem: $viewModel.alertItem)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    
                    BookFormatList(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    
                    let countPage = viewModel.countPagesConfiguration(for: book.library)
                    if countPage.isEnabled {
                        BookCountPagesCorner(book: book, lastUpdated: book.lastUpdated, countPage: countPage, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 32) {
                    BookCoverView(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, alertItem: $viewModel.alertItem)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        BookMetadataSection(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        
                        BookConnectivitySection(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat, alertItem: $viewModel.alertItem)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        
                        BookFormatList(viewModel: viewModel, book: book, lastUpdated: book.lastUpdated, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        
                        let countPage = viewModel.countPagesConfiguration(for: book.library)
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
}
