//
//  WebViewUI.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import Foundation
import SwiftUI
import WebKit

struct WebViewUI : UIViewRepresentable {

    let headerString = "<head><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'></head>"
    let content: String
    let baseURL: URL?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(headerString + content, baseURL: baseURL)
        print("WebViewUI \(content) \(baseURL?.absoluteString)")
    }
    
}
