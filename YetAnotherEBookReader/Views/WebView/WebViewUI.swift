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

    let headerString = """
        <head>
        <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'>
        <style>
        @media (prefers-color-scheme: dark) {
            body {
                background-color: rgb(38,38,41);
                color: white;
            }
            a:link {
                color: #0096e2;
            }
            a:visited {
                color: #9d57df;
            }
        }
        </style>
        </head>
        """
    let content: String
    let baseURL: URL?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        DispatchQueue.main.async {
            uiView.loadHTMLString(headerString + content, baseURL: baseURL)
        }
//        print("WebViewUI \(content) \(baseURL?.absoluteString)")
    }
    
}
