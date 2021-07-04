//
//  WebViewUIVC.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/30.
//

import UIKit
import WebKit
class WebViewUIVC: UIViewController, WKUIDelegate {
    
    var webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    var content = ""
    var baseURL: URL?
    
    override func loadView() {
        webView.uiDelegate = self
        view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //let myURL = URL(string:"https://www.apple.com")
        //let myRequest = URLRequest(url: myURL!)
        //webView.loadHTMLString(content, baseURL: baseURL)
    }
}

