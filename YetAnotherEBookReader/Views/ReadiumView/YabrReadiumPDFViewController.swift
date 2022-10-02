//
//  YabrReadiumPDFViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import Foundation
import UIKit
import R2Navigator
import R2Shared

final class YabrReadiumPDFViewController: YabrReadiumReaderViewController, PDFNavigatorDelegate {
    
    init(publication: Publication, book: Book) {
        let navigator = PDFNavigatorViewController(publication: publication, initialLocation: book.progressionLocator)
        
        super.init(navigator: navigator, publication: publication, book: book)
        
        navigator.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override var currentBookmark: Bookmark? {
        guard
            let locator = navigator.currentLocation,
            let resourceIndex = publication.readingOrder.firstIndex(withHREF: locator.href) else
        {
            return nil
        }

        return Bookmark(
            bookID: book.id,
            resourceIndex: resourceIndex,
            locator: locator
        )
    }

    override func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        super.navigator(navigator, locationDidChange: locator)
        
        var updatedReadingPosition = (Double(), Double(), [String: Any](), "")
        
        updatedReadingPosition.2["pageNumber"] = locator.locations.position
        updatedReadingPosition.2["maxPage"] = self.publication.positionsByReadingOrder.first?.count ?? 1

        updatedReadingPosition.2["pageOffsetX"] = 0
        
        updatedReadingPosition.0 = locator.locations.progression ?? 0.0
        updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
        
        if let title = locator.title {
            updatedReadingPosition.3 = title
        } else if let fragment = locator.locations.fragments.first,
                  let tocLink = publication.tableOfContents.firstDeep(withFRAGMENT: fragment),
                  let tocTitle = tocLink.title {
            updatedReadingPosition.3 = tocTitle
        } else if let fragment = locator.locations.fragments.first,
                  let locPageNumberValue = fragment.split(separator: "=").last,
                  let locPageNumber = Int(locPageNumberValue),
                    let tocLink = publication.tableOfContents.filter( { link in
                        guard let tocFragmentIndex = link.href.firstIndex(of: "#"),
                              let tocFragment = link.href[tocFragmentIndex..<link.href.endIndex] as Substring?,
                              let pageNumberValue = tocFragment.split(separator: "=").last,
                              let pageNumber = Int(pageNumberValue),
                              pageNumber <= locPageNumber
                        else { return false }
                        
                        return true
                    }).last,
                  let tocTitle = tocLink.title {
            updatedReadingPosition.3 = tocTitle
        } else {
            updatedReadingPosition.3 = "Unknown Title"
        }
        
        self.readiumMetaSource?.yabrReadiumReadPosition(self, update: updatedReadingPosition)
    }
}

fileprivate extension Array where Element == Link {
    func firstDeep(withFRAGMENT fragment: String) -> Link? {
        return first {
            URL(string: $0.href)?.fragment == fragment || $0.children.firstDeep(withFRAGMENT: fragment) != nil
        }
    }
}
