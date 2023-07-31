//
//  MDictView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/30.
//

import Foundation
import UIKit
import WebKit
import NaturalLanguage

class MDictViewContainer : UIViewController {
    let webView = DictWebView()
    var webTextColor: UIColor? = nil
    //model
    var viewModel: DictViewModel!
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        print("MDICT viewDidLoad \(self.view.frame)")
        
        webView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        guard webView.url?.host == nil,
              let server = viewModel.server,
              var word = viewModel.word
        else {
            return
        }
        
        if word.contains(" ") == false {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = word
            tagger.enumerateTags(in: word.startIndex..<word.endIndex, unit: .word, scheme: .lemma) { tag, tokenRange in
                print("\(#function) word=\(word) tag=\(String(describing: tag)) tokenRange=\(tokenRange)")
                if let tagRaw = tag?.rawValue {
                    word = tagRaw
                    return true
                }
                return false
            }
        }
        
        webView.scrollView.backgroundColor = .clear
//        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .clear
        
        super.viewWillAppear(animated)
        
        guard var urlComponent = URLComponents(string: server)
        else {
            webView.loadHTMLString("""
            <html>
            <body>
            <p>Error parsing server url</p>
            </body>
            </html>
            """, baseURL: nil)
            return
        }
        
        urlComponent.queryItems = [
            .init(name: "word", value: word.lowercased()),
        ]
        
        guard let url = urlComponent.url
        else {
            webView.loadHTMLString("""
            <html>
            <body>
            <p>Error generating request url</p>
            </body>
            </html>
            """, baseURL: nil)
            return
        }
        
        Task {
            await self.loadWebView(url)
        }
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        guard webView.superview == nil else { return }
        
        view.addSubview(webView)
        view.sendSubviewToBack(webView)
        
        let constraints = [
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        
        NSLayoutConstraint.activate(constraints)
        
        tabBarController?.navigationItem.leftBarButtonItems?[1].isEnabled = webView.canGoBack
        tabBarController?.navigationItem.leftBarButtonItems?[2].isEnabled = webView.canGoForward
    }
    
    func loadWebView(_ url: URL) async {
        guard let host = url.host
        else {
            return
        }
        
        if let color = webView.backgroundColor?.hexString(false),
           let cookie = HTTPCookie(properties: [
            .path: url.path.replacingOccurrences(of: "/lookup", with: ""),
            .name: "backgroundColor",
            .value:  color,
            .domain: host
        ]) {
            print("\(#function) \(cookie.name)=\(cookie.value)")
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
        
        if let color = webTextColor?.hexString(false),
           let cookie = HTTPCookie(properties: [
            .path: url.path.replacingOccurrences(of: "/lookup", with: ""),
            .name: "textColor",
            .value: color,
            .domain: host
        ]) {
            print("\(#function) \(cookie.name)=\(cookie.value)")
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
        
        let request = URLRequest(url: url)
        self.webView.load(request)
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        webView.removeFromSuperview()
        
        webView.loadHTMLString("""
            <html>
            <head>
            <style>body { background-color: \(webView.backgroundColor?.hexString(false) ?? "#") }</style>
            </head>
            <body>
            </body>
            </html>
            """, baseURL: nil)
        
        super.viewDidAppear(animated)
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
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    }
}
