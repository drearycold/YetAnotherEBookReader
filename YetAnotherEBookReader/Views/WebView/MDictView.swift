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
    var word = ""
    
    open override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        print("MDICT viewDidLoad \(self.view.frame)")

        // let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView()
        webView.uiDelegate = self
        view.addSubview(webView)
        
        let constraints = [
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        
        NSLayoutConstraint.activate(constraints)
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        if let url = URL(string: server) {
            webView.load(URLRequest(url: url))
        }
        
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        word = self.title ?? "_"
        if let url = URL(string: server + "?word=" + word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
            webView.load(URLRequest(url: url))
        }
        
        super.viewWillAppear(animated)
    }
    
    open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate { context in
        } completion: { context in
            print("MDICTTRANS \(self.view.frame)")
            //self.webView.frame = self.view.frame
        }

    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
}
