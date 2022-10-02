//
//  YabrReadiumCBZViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

//
//  CBZViewController.swift
//  r2-testapp-swift
//
//  Created by Alexandre Camilleri on 6/28/17.
//
//  Copyright 2018 European Digital Reading Lab. All rights reserved.
//  Licensed to the Readium Foundation under one or more contributor license agreements.
//  Use of this source code is governed by a BSD-style license which is detailed in the
//  LICENSE file present in the project repository where this source code is maintained.
//

import UIKit
import R2Navigator
import R2Shared
import R2Streamer


class YabrReadiumCBZViewController: YabrReadiumReaderViewController {

    init(publication: Publication, book: Book) {
        let navigator = CBZNavigatorViewController(publication: publication, initialLocation: book.progressionLocator)
        
        super.init(navigator: navigator, publication: publication, book: book)
        
        navigator.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
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
        updatedReadingPosition.2["maxPage"] = self.publication.readingOrder.count
        updatedReadingPosition.2["pageOffsetX"] = 0
        updatedReadingPosition.0 = locator.locations.progression ?? 0.0
        updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
        
        if 1.0 / Double(locator.locations.position ?? Int.max) + updatedReadingPosition.1 > 0.999 {
            updatedReadingPosition.1 = 1.0
        }
        
        if let title = locator.title {
            updatedReadingPosition.3 = title
        } else if let pageNumber = locator.locations.position {
            updatedReadingPosition.3 = "Page \(pageNumber)"
        } else {
            updatedReadingPosition.3 = "Untitled Page"
        }
        
        self.readiumMetaSource?.yabrReadiumReadPosition(self, update: updatedReadingPosition)
    }
}

extension YabrReadiumCBZViewController: CBZNavigatorDelegate {
}
