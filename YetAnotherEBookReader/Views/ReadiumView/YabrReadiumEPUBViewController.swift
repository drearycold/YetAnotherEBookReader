//
//  YabrReadiumEPUBViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/29.
//

import Foundation
import UIKit
import ReadiumShared
import ReadiumNavigator

import ReadiumAdapterGCDWebServer

class YabrReadiumEPUBViewController: YabrReadiumReaderViewController {


    var popoverUserconfigurationAnchor: UIBarButtonItem?

    init(publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        let navigator = try! EPUBNavigatorViewController(publication: publication, initialLocation: initialLocation, httpServer: environment.httpServer)

        super.init(navigator: navigator, publication: publication, initialLocation: initialLocation, environment: environment)

        navigator.delegate = self
    }
    
    var epubNavigator: EPUBNavigatorViewController {
        return navigator as! EPUBNavigatorViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons = super.makeNavigationBarButtons()

        // User configuration button
//        let userSettingsButton = UIBarButtonItem(image: #imageLiteral(resourceName: "settingsIcon"), style: .plain, target: self, action: #selector(presentUserSettings))
//        buttons.insert(userSettingsButton, at: 1)
//        popoverUserconfigurationAnchor = userSettingsButton

        return buttons
    }
    
/*
    override var currentBookmark: Bookmark? {
        guard
            let locator = navigator.currentLocation,
            let resourceIndex = publication.readingOrder.firstIndex(withHREF: locator.href) else
        {
            return nil
        }
        return Bookmark(bookID: book.id, resourceIndex: resourceIndex, locator: locator)
    }
*/
    
    override func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        super.navigator(navigator, locationDidChange: locator)
        
        print("EpubReadiumReaderContainerNavigatorDelegate \(locator)")
        print("EpubReadiumReaderContainerNavigatorDelegate otherLocations=\(locator.locations.otherLocations)")
        
        Task {
            var updatedReadingPosition = (Double(), Double(), [String: Any](), "")
            
            if let index = publication.readingOrder.firstIndexWithHREF(locator.href) {
                updatedReadingPosition.2["pageNumber"] = index + 1
            } else {
                updatedReadingPosition.2["pageNumber"] = 1
            }
            updatedReadingPosition.2["maxPage"] = self.publication.readingOrder.count
            updatedReadingPosition.2["pageOffsetX"] = locator.locations.position
            
            updatedReadingPosition.0 = locator.locations.progression ?? 0.0
            updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
            
            let tocResult = await publication.tableOfContents()
            let tableOfContents = (try? tocResult.get()) ?? []
            
            if let title = locator.title {
                updatedReadingPosition.3 = title
            } else if let tocLink = tableOfContents.firstDeep(withHREF: locator.href.string),
                      let tocTitle = tocLink.title {
                updatedReadingPosition.3 = tocTitle
            } else {
                updatedReadingPosition.3 = "Unknown Chapter"
            }
            
            DispatchQueue.main.async {
                self.readiumMetaSource?.yabrReadiumReadPosition(self, update: updatedReadingPosition)
            }
        }
    }
}

fileprivate extension Array where Element == Link {
    func firstDeep(withHREF href: String) -> Link? {
        return first {
            $0.href == href || URL(string: $0.href)?.path == href || $0.children.firstDeep(withHREF: href) != nil
        }
    }
}

extension YabrReadiumEPUBViewController: EPUBNavigatorDelegate {
    
}

extension YabrReadiumEPUBViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
}

extension YabrReadiumEPUBViewController: UIPopoverPresentationControllerDelegate {
    // Prevent the popOver to be presented fullscreen on iPhones.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
    {
        return .none
    }
}


/*
extension YabrReadiumEPUBViewController: ReaderModuleDelegate {
    func presentAlert(_ title: String, message: String, from viewController: UIViewController) {
        print("ReaderModuleDelegateImpl alert \(title) \(message)")
    }
    
    func presentError(_ error: Error?, from viewController: UIViewController) {
        if let error = error {
            print("ReaderModuleDelegateImpl error \(error)")
        }
    }
}
*/


