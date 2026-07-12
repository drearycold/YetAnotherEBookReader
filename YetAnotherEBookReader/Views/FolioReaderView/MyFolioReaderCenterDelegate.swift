//
//  File.swift
//  
//
//  Created by 京太郎 on 2021/4/6.
//

import Foundation
import UIKit
import FolioReaderKit

enum FolioAdvancedQAMenuConfiguration {
    static func apply(to configuration: FolioReaderConfig, isAvailable: Bool) {
        configuration.enableMDictViewer = isAvailable
        configuration.localizedMDictMenu = "Reader QA"
    }
}

public class MyFolioReaderCenterDelegate: FolioReaderCenterDelegate {
    var pageDidAppearHandler: ((FolioReaderPage) -> Void)?
    var pageItemChangedHandler: ((Int) -> Void)?
    
    public init() {
        
    }
    
    @objc public func htmlContentForPage(_ page: FolioReaderPage, htmlContent: String) -> String {
        
        // print(htmlContent)
        let regex = try! NSRegularExpression(pattern: "background=\"[^\"]+\"", options: .caseInsensitive)
        
        
        let modified = regex.stringByReplacingMatches(in: htmlContent, options: [], range: NSMakeRange(0, htmlContent.count), withTemplate: "").replacingOccurrences(of: "<body ", with: "<body style=\"text-align: justify !important; display: block !important; \" ")
        // print(modified)
        return modified
    }

    @objc public func pageDidAppear(_ page: FolioReaderPage) {
        pageDidAppearHandler?(page)
    }

    @objc public func pageItemChanged(_ pageNumber: Int) {
        pageItemChangedHandler?(pageNumber)
    }
}

public class YabrFolioReaderPageDelegate: FolioReaderPageDelegate {
    let readerConfig: FolioReaderConfig
    let dictNav = UINavigationController()
    
    init(readerConfig: FolioReaderConfig, book: CalibreBook, resolverProvider: @escaping () -> FolioReaderReferenceResolving?) {
        self.readerConfig = readerConfig
        MainActor.assumeIsolated {
            dictNav.setViewControllers([FolioAdvancedQAViewController(book: book, resolverProvider: resolverProvider)], animated: false)
        }
        
        dictNav.navigationBar.isTranslucent = false
        dictNav.isToolbarHidden = true
    }
        
    @objc public func pageWillLoad(_ page: FolioReaderPage) {
        guard let webView = page.webView else { return }
        
        webView.setMDictView(mDictView: dictNav)
    }
    
    @objc public func pageStyleChanged(_ page: FolioReaderPage, _ reader: FolioReader) {
        let backgroundColor = readerConfig.themeModeBackground[reader.themeMode]
        let textColor = readerConfig.themeModeTextColor[reader.themeMode]
        let navBackgroundColor = readerConfig.themeModeNavBackground[reader.themeMode]
        
        dictNav.navigationBar.tintColor = textColor
        dictNav.navigationBar.backgroundColor = backgroundColor
        dictNav.navigationBar.barTintColor = navBackgroundColor
        dictNav.navigationBar.titleTextAttributes = [
            .foregroundColor: textColor
        ]
        
        dictNav.view.backgroundColor = backgroundColor
    }
}
