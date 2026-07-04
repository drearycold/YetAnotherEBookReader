//
//  BookMetadataSection.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookMetadataSection: View {
    @Environment(\.openURL) var openURL
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool
    

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                metadataIcon(systemName: "building.columns")
                Text("\(book.library.name) - \(book.id) @ Server \(book.library.server.name)")
            }
            HStack {
                metadataIcon(systemName: "face.smiling")
                Text(book.ratingDescription)
                if let ratingGRDescription = viewModel.ratingGRDescription(for: book) {
                    Text(" (\(ratingGRDescription))")
                }
            }
            HStack {
                if book.authors.count <= 1 {
                    metadataIcon(systemName: "person")
                } else if book.authors.count == 2 {
                    metadataIcon(systemName: "person.2")
                } else {
                    metadataIcon(systemName: "person.3")
                }
                Text(book.authorsDescription)
            }
            HStack {
                metadataIcon(systemName: "house")
                Text(book.publisher)
            }
            HStack {
                metadataIcon(systemName: "calendar")
                Text(book.pubDateByLocale)
            }
            HStack {
                metadataIcon(systemName: "tray.2")
                Text("\(book.seriesDescription) (\(book.seriesIndexDescription))")
            }
            
            HStack {
                metadataIcon(systemName: "tag")
                Text(book.tagsDescription)
            }
            
            HStack {
                metadataIcon(systemName: "link")
                
                Button(action:{
                    var url: URL? = nil
                    defer {
                        if let url = url {
                            openURL(url)
                        }
                    }
                    
                    if let goodreadsId = book.identifiers["goodreads"] {
                       url = URL(string: "https://www.goodreads.com/book/show/\(goodreadsId)")
                    } else if var urlComponents = URLComponents(string: "https://www.goodreads.com/search") {
                        urlComponents.queryItems = [URLQueryItem(name: "q", value: book.title + " " + book.authors.joined(separator: " "))]
                        url = urlComponents.url
                    }
                }) {
                    metadataLinkIcon("icon-goodreads", matched: book.identifiers["goodreads"] != nil)
                }
                
                Button(action:{
                    var url: URL? = nil
                    defer {
                        if let url = url {
                            openURL(url)
                        }
                    }
                    
                    if let id = book.identifiers["amazon"] {
                       url = URL(string: "http://www.amazon.com/dp/\(id)")
                    } else if var urlComponents = URLComponents(string: "https://www.amazon.com/s") {
                        urlComponents.queryItems = [URLQueryItem(name: "k", value: book.title + " " + book.authors.joined(separator: " "))]
                        url = urlComponents.url
                    }
                }) {
                    metadataLinkIcon("icon-amazon", matched: book.identifiers["amazon"] != nil)
                }
            }
            
            Group {
                HStack {
                    metadataIcon(systemName: "envelope.open")
                    Text(book.lastModifiedByLocale)
                }
                
                BookProgressSection(viewModel: viewModel, book: book, lastUpdated: lastUpdated, isCompat: isCompat)
                
                HStack {
                    metadataIcon(systemName: "books.vertical")
                    if let shelves = viewModel.goodreadsShelves(for: book) {
                        Text(shelves.joined(separator: ", "))
                    } else {
                        Text("Unspecified")
                    }
                }
            }
        }
        .lineLimit(2)
        .font(.subheadline)
    }
    
    private func metadataIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 24, alignment: .center)
    }
    
    private func metadataLinkIcon(_ name: String, matched: Bool = false) -> some View {
        HStack(alignment: .top, spacing: -2) {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            if matched == false {
                Image(systemName: "questionmark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
            }
        }
    }
}
