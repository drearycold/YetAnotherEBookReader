//
//  DictTabBarController.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/7/29.
//

import Foundation

import UIKit
import WebKit

class DictTabBarController: UITabBarController {
    let mDictView = MDictViewContainer()
    let encycloView = EncycloView()
    
    let editor = MDictViewEdit()

    //model
    var viewModel: DictViewModel = .init()
    
    override func viewDidLoad() {
        mDictView.viewModel = viewModel
        mDictView.webView.navigationDelegate = self

        encycloView.viewModel = viewModel
        encycloView.webView.navigationDelegate = self
        
        editor.viewModel = viewModel
        
        mDictView.tabBarItem = .init(title: "Calibre", image: UIImage(systemName: "character.book.closed"), tag: 0)
        encycloView.tabBarItem = .init(title: "Baike", image: UIImage(systemName: "b.circle"), tag: 1)
        
        viewControllers = [mDictView, encycloView]
        viewModel.tabWebView = [mDictView.webView, encycloView.webView]
        
        tabBar.isTranslucent = false
        
        self.navigationItem.setLeftBarButtonItems(
            [
                UIBarButtonItem(title: "Close", primaryAction: .init(handler: { _ in
                    self.dismiss(animated: true, completion: nil)
                })),
                UIBarButtonItem(
                    image: UIImage(systemName: "chevron.backward"),
                    primaryAction: UIAction { action in
                        self.viewModel.tabWebView[self.selectedIndex].goBack()
                    }
                ),
                UIBarButtonItem(
                    image: UIImage(systemName: "chevron.forward"),
                    primaryAction: UIAction { action in
                        self.viewModel.tabWebView[self.selectedIndex].goForward()
                    }
                )
            ],
            animated: true
        )
        
        updateNavigationButtons()
        
        viewModel.server = UserDefaults.standard.url(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)?.absoluteString

        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        viewModel.word = self.navigationController?.title ?? "_"
        
        if let commitWord = editor.commitWord {
            viewModel.word = commitWord
            editor.commitWord = nil
        }
        
        self.navigationItem.title = viewModel.word
        
        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                title: "List",
                image: UIImage(systemName: "list.bullet"),
                menu: UIMenu(children: [])
            ),
            UIBarButtonItem(
                image: UIImage(systemName: "character.cursor.ibeam"),
                primaryAction: .init(handler: { [self] _ in
                    editor.view.backgroundColor = self.view.backgroundColor
                    
                    editor.editTextView.text = navigationItem.title
                    editor.editTextView.textColor = self.navigationController?.navigationBar.tintColor
                    
                    editor.editTextHintView.tintColor = self.navigationController?.navigationBar.tintColor
                    
                    self.navigationController?.pushViewController(editor, animated: true)
                })
            )
        ]
        
        self.navigationItem.rightBarButtonItems?[0].isEnabled = false
        
        super.viewWillAppear(animated)
    }
    
    func updateNavigationButtons() {
        let webView = viewModel.tabWebView[selectedIndex]
        navigationItem.leftBarButtonItems?[1].isEnabled = webView.canGoBack
        navigationItem.leftBarButtonItems?[2].isEnabled = webView.canGoForward
        
        navigationItem.rightBarButtonItems?[0].isEnabled = false
        navigationItem.rightBarButtonItems?[0].menu = nil
    }
}

extension DictTabBarController: UITabBarControllerDelegate {
    override func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        updateNavigationButtons()
    }
}

extension DictTabBarController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard let dictWebView = webView as? DictWebView
        else {
            return
        }
        
        dictWebView.activityView.color = self.navigationController?.navigationBar.tintColor
        dictWebView.activityView.backgroundColor = self.navigationController?.navigationBar.backgroundColor?.withAlphaComponent(0.9)
        dictWebView.activityView.startAnimating()
        
        dictWebView.labelView.textColor = self.navigationController?.navigationBar.tintColor
        dictWebView.labelView.text = "Loading..."
        dictWebView.labelView.backgroundColor = self.navigationController?.navigationBar.backgroundColor?.withAlphaComponent(0.9)
        dictWebView.labelView.isHidden = false
    }
    
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let dictWebView = webView as? DictWebView
        else {
            return
        }
        
        dictWebView.activityView.stopAnimating()
        dictWebView.labelView.text = nil
        dictWebView.labelView.isHidden = true
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView == mDictView.webView {
            print("\(#function) didFinish=\(String(describing: navigation))")
            guard viewModel.server != nil,
                  webView.url?.host != nil else { return }
            
            if let url = webView.url,
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let word = components.queryItems?.first(where: { $0.name == "word" })?.value {
                self.navigationItem.title = word
                viewModel.word = word
            }
            
            let navWord = viewModel.word
            
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
                let menuItems = array.compactMap({ item -> UIAction? in
                    guard let a = item as? NSDictionary, let id = a["id"] as? String, let name = a["name"] as? String else { return nil }
                    return UIAction(title: name, image: nil, identifier: nil, discoverabilityTitle: nil, attributes: [], state: .off) { action in
                        print("\(#function) id=\(id) name=\(name)")
                        webView.evaluateJavaScript("document.getElementById('\(id)').offsetTop") { result, error in
                            if let offset = result as? CGFloat {
                                webView.scrollView.contentOffset.y = offset - (self.navigationController?.navigationBar.frame.height ?? 0)
                            }
                        }
                    }
                })
                
                if self.selectedIndex == 0,
                   self.viewModel.word == navWord {
                    let menu = UIMenu(title: "Dictionary", image: nil, identifier: nil, options: [], children: menuItems)
                    self.navigationItem.rightBarButtonItems?[0] = UIBarButtonItem(
                        title: "List",
                        image: UIImage(systemName: "list.bullet"),
                        menu: menu
                    )
                }
            }
        }
        if webView == encycloView.webView {
            
        }
        
        updateNavigationButtons()
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let dictWebView = webView as? DictWebView
        else {
            return
        }
        
        dictWebView.activityView.stopAnimating()
        dictWebView.labelView.text = error.localizedDescription
        dictWebView.labelView.isHidden = false
        
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(.init(title: "Dismiss", style: .cancel))
        self.present(alert, animated: true)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let dictWebView = webView as? DictWebView
        else {
            return
        }
        
        dictWebView.activityView.stopAnimating()
        dictWebView.labelView.text = error.localizedDescription
        dictWebView.labelView.isHidden = false
            
        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(.init(title: "Dismiss", style: .cancel))
        self.present(alert, animated: true)
    }
    
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let dictWebView = webView as? DictWebView
        else {
            return
        }
        
        dictWebView.labelView.text = "Terminated"
        dictWebView.labelView.isHidden = false
    }
}
