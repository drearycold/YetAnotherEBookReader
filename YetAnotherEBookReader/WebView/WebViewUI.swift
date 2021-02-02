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
    
    func makeUIViewController(context: Context) -> WebViewUIVC {
        return webView
    }
    
    func updateUIViewController(_ uiViewController: WebViewUIVC, context: Context) {
        webView.webView.loadHTMLString(webView.content, baseURL: nil)
    }
    
    func setContent(_ content: String, _ baseURL: URL?) {
        webView.content = content
        webView.webView.loadHTMLString(webView.content, baseURL: baseURL)
    }
}
