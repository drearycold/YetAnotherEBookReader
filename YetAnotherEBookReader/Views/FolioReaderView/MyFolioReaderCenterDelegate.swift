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
    
    init(readerConfig: FolioReaderConfig) {
        self.readerConfig = readerConfig
    }
        
    @objc public func pageWillLoad(_ page: FolioReaderPage) {
        guard let webView = page.webView else { return }
        let mDictView = MDictViewContainer()
        webView.setMDictView(mDictView: mDictView)
    }
    
}
