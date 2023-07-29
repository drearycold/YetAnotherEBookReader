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
        encycloView.viewModel = viewModel
        editor.viewModel = viewModel
        
        mDictView.tabBarItem = .init(title: "Calibre", image: UIImage(systemName: "character.book.closed"), tag: 0)
        encycloView.tabBarItem = .init(title: "Baike", image: UIImage(systemName: "b.circle"), tag: 1)
        
        viewControllers = [mDictView, encycloView]
        
        tabBar.isTranslucent = false
        
        self.navigationItem.setLeftBarButtonItems(
            [
                UIBarButtonItem(title: "Close", primaryAction: .init(handler: { _ in
                    self.dismiss(animated: true, completion: nil)
                })),
                UIBarButtonItem(
                    image: UIImage(systemName: "chevron.backward"),
                    primaryAction: UIAction { action in
                        print("\(#function) backward action")
                        switch self.selectedIndex {
                        case 0:
                            if self.mDictView.webView.canGoBack {
                                self.mDictView.webView.goBack()
                            }
                        case 1:
                            if self.encycloView.webView.canGoBack {
                                self.encycloView.webView.goBack()
                            }
                        default:
                            break
                        }
                    }
                ),
                UIBarButtonItem(
                    image: UIImage(systemName: "chevron.forward"),
                    primaryAction: UIAction { action in
                        print("\(#function) forward action")
                        switch self.selectedIndex {
                        case 0:
                            if self.mDictView.webView.canGoForward {
                                self.mDictView.webView.goForward()
                            }
                        case 1:
                            if self.encycloView.webView.canGoForward {
                                self.encycloView.webView.goForward()
                            }
                        default:
                            break
                        }
                    }
                )
            ],
            animated: true
        )
        self.navigationItem.leftBarButtonItems?[1].isEnabled = false
        self.navigationItem.leftBarButtonItems?[2].isEnabled = false
        
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
}
