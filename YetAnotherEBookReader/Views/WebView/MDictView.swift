//
//  MDictView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/30.
//

import Foundation
import UIKit
import WebKit

open class MDictViewContainer : UIViewController, WKUIDelegate {
    var webView: WKWebView!
    var server = "http://peter-mdict.lan/"
    open var word = ""
    
    open override func viewDidLoad() {
        self.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: view.frame, configuration: webConfiguration)
        webView.uiDelegate = self
        view.addSubview(webView)
        
        if let url = URL(string: server) {
            webView.load(URLRequest(url: url))
        }
        
        let constraints = [
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        
        NSLayoutConstraint.activate(constraints)
        
        super.viewDidLoad()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        word = self.title ?? "_"
        if let url = URL(string: server + "?word=" + word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
            webView.load(URLRequest(url: url))
        }
        
        super.viewWillAppear(animated)
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}
