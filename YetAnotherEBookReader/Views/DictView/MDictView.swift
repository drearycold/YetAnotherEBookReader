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

class MDictViewContainer : UIViewController, WKUIDelegate, WKScriptMessageHandler {
    let webView = WKWebView()
    let activityView = UIActivityIndicatorView()
    let labelView = UILabel()
    
    //model
    var viewModel: DictViewModel!
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        activityView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(activityView)
        NSLayoutConstraint.activate([
            activityView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6),
            activityView.heightAnchor.constraint(equalToConstant: 32),
            activityView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        activityView.style = .medium
        activityView.hidesWhenStopped = true
        activityView.startAnimating()
        
        labelView.textAlignment = .center
        labelView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6),
            labelView.heightAnchor.constraint(equalToConstant: 96),
            labelView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            labelView.bottomAnchor.constraint(equalTo: activityView.topAnchor)
        ])

        print("MDICT viewDidLoad \(self.view.frame)")
        
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "MDictView")
        
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
        
        if let color = webView.tintColor?.hexString(false),
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

extension MDictViewContainer: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityView.color = self.navigationController?.navigationBar.tintColor
        activityView.backgroundColor = self.navigationController?.navigationBar.backgroundColor?.withAlphaComponent(0.9)
        activityView.startAnimating()
        
        labelView.textColor = self.navigationController?.navigationBar.tintColor
        labelView.text = "Loading..."
        labelView.backgroundColor = self.navigationController?.navigationBar.backgroundColor?.withAlphaComponent(0.9)
        labelView.isHidden = false
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("\(#function) didFinish=\(String(describing: navigation))")
        guard viewModel.server != nil,
              webView.url?.host != nil else { return }
        
        if let url = webView.url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let word = components.queryItems?.first(where: { $0.name == "word" })?.value {
            self.tabBarController?.navigationItem.title = word
            viewModel.word = word
        }
        tabBarController?.navigationItem.leftBarButtonItems?[1].isEnabled = webView.canGoBack
        tabBarController?.navigationItem.leftBarButtonItems?[2].isEnabled = webView.canGoForward

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
            self.tabBarController?.navigationItem.rightBarButtonItems?[0] = UIBarButtonItem(
                    title: "List",
                    image: UIImage(systemName: "list.bullet"),
                    menu: menu
                )
            
            self.activityView.stopAnimating()
            self.labelView.text = nil
            self.labelView.isHidden = true
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityView.stopAnimating()
        labelView.text = error.localizedDescription
        labelView.isHidden = false
        
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(.init(title: "Dismiss", style: .cancel))
        self.present(alert, animated: true)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityView.stopAnimating()
        labelView.text = error.localizedDescription
        labelView.isHidden = false
        
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(.init(title: "Dismiss", style: .cancel))
        self.present(alert, animated: true)
    }
    
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        labelView.text = "Terminated"
        labelView.isHidden = false
    }
}
