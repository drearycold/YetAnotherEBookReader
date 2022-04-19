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
    let webView = WKWebView()
    var server: String?
    var word = ""
    
    open override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        print("MDICT viewDidLoad \(self.view.frame)")
        
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
        
        let enabled = UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_ENABLED)
        guard enabled else { return }
        
        server = UserDefaults.standard.url(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)?.absoluteString
        guard let server = server else { return }
        
        if let url = URL(string: server) {
            webView.load(URLRequest(url: url))
        }
        
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        guard let server = server else { return }

        word = self.title ?? "_"
        if let url = URL(string: server + "?word=" + word.lowercased().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
            webView.load(URLRequest(url: url))
        }
        
        self.navigationItem.title = word
        
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
