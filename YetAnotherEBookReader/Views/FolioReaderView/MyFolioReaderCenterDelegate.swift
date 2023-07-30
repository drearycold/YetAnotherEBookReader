//
//  File.swift
//  
//
//  Created by 京太郎 on 2021/4/6.
//

import Foundation

import FolioReaderKit

public class MyFolioReaderCenterDelegate: FolioReaderCenterDelegate {
    
    public init() {
        
    }
    
    @objc public func htmlContentForPage(_ page: FolioReaderPage, htmlContent: String) -> String {
        
        // print(htmlContent)
        let regex = try! NSRegularExpression(pattern: "background=\"[^\"]+\"", options: .caseInsensitive)
        
        
        let modified = regex.stringByReplacingMatches(in: htmlContent, options: [], range: NSMakeRange(0, htmlContent.count), withTemplate: "").replacingOccurrences(of: "<body ", with: "<body style=\"text-align: justify !important; display: block !important; \" ")
        // print(modified)
        return modified
    }
}

public class YabrFolioReaderPageDelegate: FolioReaderPageDelegate {
    let readerConfig: FolioReaderConfig
//    let dictController = DictTabBarController()
    let dictNav = UINavigationController()
    let dictTab = DictTabBarController()
    
    init(readerConfig: FolioReaderConfig) {
        self.readerConfig = readerConfig
        
        dictNav.setViewControllers([dictTab], animated: false)
        
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
        
        
        dictTab.mDictView.webTextColor = reader.isNight(textColor, nil)
        dictTab.mDictView.webView.backgroundColor = backgroundColor
        
        dictTab.view.backgroundColor = backgroundColor

        dictNav.navigationBar.tintColor = textColor
        dictNav.navigationBar.backgroundColor = backgroundColor
        dictNav.navigationBar.barTintColor = navBackgroundColor
        dictNav.navigationBar.titleTextAttributes = [
            .foregroundColor: textColor
        ]
        
        dictTab.tabBar.tintColor = textColor
        dictTab.tabBar.backgroundColor = backgroundColor
        dictTab.tabBar.barTintColor = navBackgroundColor
    }
}
