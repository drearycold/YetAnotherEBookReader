//
//  WebViewUI.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import Foundation
import SwiftUI


struct WebViewUI : UIViewControllerRepresentable {

    var webView = WebViewUIVC()
    let headerString = "<head><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'></head>"
    
    func makeUIViewController(context: Context) -> WebViewUIVC {
        return webView
    }
    
    func updateUIViewController(_ uiViewController: WebViewUIVC, context: Context) {
        webView.webView.loadHTMLString(headerString + webView.content, baseURL: nil)
    }
    
    func setContent(_ content: String, _ baseURL: URL?) {
        webView.content = content
        webView.webView.loadHTMLString(headerString + webView.content, baseURL: baseURL)
        
    }
}
