//
//  YabrReaderNavigationViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Gemini CLI on 2024/03/26.
//

import SwiftUI
import Combine
import ReadiumShared
import ReadiumNavigator

class YabrReaderNavigationViewModel: ObservableObject {
    let publication: Publication
    
    @Published var outline: [ReadiumShared.Link] = []
    @Published var bookmarks: [Locator] = []
    @Published var highlights: [Locator] = []
    
    var onNavigateToLocator: ((Locator) -> Void)?
    var onNavigateToLink: ((ReadiumShared.Link) -> Void)?
    
    init(publication: Publication) {
        self.publication = publication
        
        Task {
            let result = await publication.tableOfContents()
            DispatchQueue.main.async {
                self.outline = (try? result.get()) ?? []
            }
        }
    }
    
    func loadAnnotations(book: CalibreBook?) {
        guard let book = book else { return }
        
        // Load Bookmarks
        let bookBookmarks = book.readPos.bookmarks()
        self.bookmarks = bookBookmarks.compactMap { b in
            // Assuming 'pos' contains the Locator JSON
            return try? Locator(jsonString: b.pos)
        }
        
        // Load Highlights
        let bookHighlights = book.readPos.highlights()
        self.highlights = bookHighlights.compactMap { h in
            if let cfi = h.cfiStart, let href = AnyURL(legacyHREF: h.spineName ?? "") {
                return Locator(
                    href: href,
                    mediaType: .html, // Default for EPUB spine items
                    locations: .init(fragments: [cfi]),
                    text: .init(highlight: h.content)
                )
            }
            return nil
        }
    }
}
