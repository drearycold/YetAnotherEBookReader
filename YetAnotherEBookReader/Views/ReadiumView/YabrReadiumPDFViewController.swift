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
        
        updatedReadingPosition.2["pageNumber"] = locator.locations.position
        updatedReadingPosition.2["maxPage"] = self.publication.positionsByReadingOrder.first?.count ?? 1

        updatedReadingPosition.2["pageOffsetX"] = 0
        
        updatedReadingPosition.0 = locator.locations.progression ?? 0.0
        updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
        
        updatedReadingPosition.3 = locator.title ?? ""
    }
}
