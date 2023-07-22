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

open class MDictViewContainer : UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    let webView = WKWebView()
    var server: String?
    var word = ""
    var backgroundColor = "#"
    var textColor = "#"
    
    open override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        print("MDICT viewDidLoad \(self.view.frame)")
        
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "MDictView")
        
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
        guard server != nil else { return }
        
        self.toolbarItems = [
            UIBarButtonItem(
                image: UIImage(systemName: "chevron.backward"),
                primaryAction: UIAction { action in
                    print("\(#function) backward action")
                    if self.webView.canGoBack {
                        self.webView.goBack()
                    }
                }
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "chevron.forward"),
                primaryAction: UIAction { action in
                    print("\(#function) forward action")
                    if self.webView.canGoForward {
                        self.webView.goForward()
                    }
                }
            )
        ]
        
        self.toolbarItems?[0].isEnabled = false
        self.toolbarItems?[1].isEnabled = false
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        guard let server = server else { return }

        do {
            let json = try JSONDecoder().decode([String:String].self, from: self.title?.data(using: .utf8) ?? .init())
            if let word = json["word"] {
                self.word = word
            }
            if let backgroundColor = json["backgroundColor"] {
                self.backgroundColor = backgroundColor
            } else {
                self.backgroundColor = "#"
            }
            if let textColor = json["textColor"] {
                self.textColor = textColor
            } else {
                self.textColor = "#"
            }
        } catch {
            word = self.title ?? "_"
            backgroundColor = "#"
            textColor = "#"
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
        
        self.navigationItem.title = word
        
        webView.scrollView.backgroundColor = nil
        webView.backgroundColor = nil
        webView.underPageBackgroundColor = nil
        
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
    
    func loadWebView(_ url: URL) async {
        guard let host = url.host
        else {
            return
        }
        
        if let backgroundColor = HTTPCookie(properties: [
            .path: url.path.replacingOccurrences(of: "/lookup", with: ""),
            .name: "backgroundColor",
            .value: backgroundColor,
            .domain: host
        ]) {
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(backgroundColor)
        }
        
        if let textColor = HTTPCookie(properties: [
            .path: url.path.replacingOccurrences(of: "/lookup", with: ""),
            .name: "textColor",
            .value: textColor,
            .domain: host
        ]) {
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(textColor)
        }
        
        var request = URLRequest(url: url)
//        request.httpShouldHandleCookies = true
//        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.webView.load(request)
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
//        webView.loadHTMLString("""
//            <html>
//            <body>
//            </body>
//            </html>
//            """, baseURL: nil)
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
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("\(#function) didFinish=\(String(describing: navigation))")
        if let url = webView.url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let word = components.queryItems?.first(where: { $0.name == "word" })?.value {
            self.navigationItem.title = word
        }
        toolbarItems?[0].isEnabled = webView.canGoBack
        toolbarItems?[1].isEnabled = webView.canGoForward

        webView.evaluateJavaScript(
            """
            var mdict_def = document.getElementsByClassName("mdictDefinition")
            var names = []
            for (var i=0; i<mdict_def.length; i+=1) {
                var h = mdict_def.item(i).getElementsByTagName("h5")[0]
                names.push({name: h.innerText, id: mdict_def.item(i).id})
            }
            names
            """
        ) { result, error in
            print("\(#function) result=\(String(describing: result)) error=\(error)")
            guard let array = result as? NSArray else { return }
            array.forEach {
                guard let a = $0 as? NSDictionary else { return }
                print("\(#function) a=\(a)")
                guard let id = a["id"], let name = a["name"] else { return }
                print("\(#function) id=\(id) name=\(name)")

            }
            let menu = UIMenu(title: "Dictionary", image: nil, identifier: nil, options: [], children: array.compactMap({
                guard let a = $0 as? NSDictionary, let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
                return UIAction(title: name, image: nil, identifier: nil, discoverabilityTitle: nil, attributes: [], state: .off) { action in
                    print("\(#function) id=\(id) name=\(name)")
                    self.webView.evaluateJavaScript("document.getElementById('\(id)').offsetTop") { result, error in
                        if let offset = result as? CGFloat {
                            self.webView.scrollView.contentOffset.y = offset - (self.navigationController?.navigationBar.frame.height ?? 0)
                        }
                    }
                }
            })
            )
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "List", image: UIImage(systemName: "list.bullet"), primaryAction: nil, menu: menu)
        }
    }
}
