//
//  EncycloView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/29.
//

import Foundation
import UIKit
import WebKit

class EncycloView: UIViewController {
    
    let webView = WKWebView(frame: .zero)

    //model
    var viewModel: DictViewModel!
    
    override func viewDidLoad() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            webView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            webView.widthAnchor.constraint(equalTo: view.widthAnchor),
            webView.heightAnchor.constraint(equalTo: view.heightAnchor),
        ])
    }
    
    override func viewWillAppear(_ animated: Bool) {
        var urlComponents = URLComponents(string: "https://wapbaike.baidu.com/item/")
        urlComponents?.path.append(viewModel.word!)
//        urlComponents?.path = urlComponents?.path.append
        
        if let url = urlComponents?.url {
            webView.load(.init(url: url))
        }
        
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        tabBarController?.navigationItem.leftBarButtonItems?[1].isEnabled = webView.canGoBack
        tabBarController?.navigationItem.leftBarButtonItems?[2].isEnabled = webView.canGoForward
        
        super.viewDidAppear(animated)
    }
}

extension EncycloView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        tabBarController?.navigationItem.leftBarButtonItems?[1].isEnabled = webView.canGoBack
        tabBarController?.navigationItem.leftBarButtonItems?[2].isEnabled = webView.canGoForward
    }
}
