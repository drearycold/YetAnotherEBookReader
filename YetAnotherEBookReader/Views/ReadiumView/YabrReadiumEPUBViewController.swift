//
//  YabrReadiumEPUBViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/29.
//

import Foundation
import UIKit
import R2Shared
import R2Navigator

//
//  EPUBViewController.swift
//  r2-testapp-swift
//
//  Created by Alexandre Camilleri on 7/3/17.
//
//  Copyright 2018 European Digital Reading Lab. All rights reserved.
//  Licensed to the Readium Foundation under one or more contributor license agreements.
//  Use of this source code is governed by a BSD-style license which is detailed in the
//  LICENSE file present in the project repository where this source code is maintained.
//

import UIKit
import R2Shared
import R2Navigator

class YabrReadiumEPUBViewController: YabrReadiumReaderViewController {

    var popoverUserconfigurationAnchor: UIBarButtonItem?
    var userSettingNavigationController: UserSettingsNavigationController

    init(publication: Publication, book: Book, resourcesServer: ResourcesServer) {
        let navigator = EPUBNavigatorViewController(publication: publication, initialLocation: book.progressionLocator, resourcesServer: resourcesServer)

        let settingsStoryboard = UIStoryboard(name: "UserSettings", bundle: nil)
        userSettingNavigationController = settingsStoryboard.instantiateViewController(withIdentifier: "UserSettingsNavigationController") as! UserSettingsNavigationController
        userSettingNavigationController.fontSelectionViewController =
            (settingsStoryboard.instantiateViewController(withIdentifier: "FontSelectionViewController") as! FontSelectionViewController)
        userSettingNavigationController.advancedSettingsViewController =
            (settingsStoryboard.instantiateViewController(withIdentifier: "AdvancedSettingsViewController") as! AdvancedSettingsViewController)
        
        super.init(navigator: navigator, publication: publication, book: book)
        
        navigator.delegate = self
    }
    
    var epubNavigator: EPUBNavigatorViewController {
        return navigator as! EPUBNavigatorViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
  
        /// Set initial UI appearance.
        if let appearance = publication.userProperties.getProperty(reference: ReadiumCSSReference.appearance.rawValue) {
            setUIColor(for: appearance)
        }
        
        let userSettings = epubNavigator.userSettings
        userSettingNavigationController.userSettings = userSettings
        userSettingNavigationController.modalPresentationStyle = .popover
        userSettingNavigationController.usdelegate = self
        userSettingNavigationController.userSettingsTableViewController.publication = publication
        

        publication.userSettingsUIPresetUpdated = { [weak self] preset in
            guard let `self` = self, let presetScrollValue:Bool = preset?[.scroll] else {
                return
            }
            
            if let scroll = self.userSettingNavigationController.userSettings.userProperties.getProperty(reference: ReadiumCSSReference.scroll.rawValue) as? Switchable {
                if scroll.on != presetScrollValue {
                    self.userSettingNavigationController.scrollModeDidChange()
                }
            }
        }
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
        let userSettingsButton = UIBarButtonItem(image: #imageLiteral(resourceName: "settingsIcon"), style: .plain, target: self, action: #selector(presentUserSettings))
        buttons.insert(userSettingsButton, at: 1)
        popoverUserconfigurationAnchor = userSettingsButton

        return buttons
    }
    
    override var currentBookmark: Bookmark? {
        guard
            let locator = navigator.currentLocation,
            let resourceIndex = publication.readingOrder.firstIndex(withHREF: locator.href) else
        {
            return nil
        }
        return Bookmark(bookID: book.id, resourceIndex: resourceIndex, locator: locator)
    }
    
    @objc func presentUserSettings() {
        let popoverPresentationController = userSettingNavigationController.popoverPresentationController!
        
        popoverPresentationController.delegate = self
        popoverPresentationController.barButtonItem = popoverUserconfigurationAnchor

        userSettingNavigationController.publication = publication
        present(userSettingNavigationController, animated: true) {
            // Makes sure that the popover is dismissed also when tapping on one of the other UIBarButtonItems.
            // ie. http://karmeye.com/2014/11/20/ios8-popovers-and-passthroughviews/
            popoverPresentationController.passthroughViews = nil
        }
    }

    override func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        super.navigator(navigator, locationDidChange: locator)
        
        print("EpubReadiumReaderContainerNavigatorDelegate \(locator)")
        print("EpubReadiumReaderContainerNavigatorDelegate otherLocations=\(locator.locations.otherLocations)")
        
        var updatedReadingPosition = (Double(), Double(), [String: Any](), "")
        
        if let index = publication.readingOrder.firstIndex(withHREF: locator.href) {
            updatedReadingPosition.2["pageNumber"] = index + 1
        } else {
            updatedReadingPosition.2["pageNumber"] = 1
        }
        updatedReadingPosition.2["maxPage"] = self.publication.readingOrder.count
        updatedReadingPosition.2["pageOffsetX"] = locator.locations.position
        
        updatedReadingPosition.0 = locator.locations.progression ?? 0.0
        updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
        
        if let title = locator.title {
            updatedReadingPosition.3 = title
        } else if let tocLink = publication.tableOfContents.firstDeep(withHREF: locator.href),
                  let tocTitle = tocLink.title {
            updatedReadingPosition.3 = tocTitle
        } else {
            updatedReadingPosition.3 = "Unknown Chapter"
        }
        
        self.readiumMetaSource?.yabrReadiumReadPosition(self, update: updatedReadingPosition)
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

extension YabrReadiumEPUBViewController: UserSettingsNavigationControllerDelegate {

    internal func getUserSettings() -> UserSettings {
        return epubNavigator.userSettings
    }
    
    internal func updateUserSettingsStyle() {
        DispatchQueue.main.async {
            self.epubNavigator.updateUserSettingStyle()
        }
    }
    
    /// Synchronyze the UI appearance to the UserSettings.Appearance.
    ///
    /// - Parameter appearance: The appearance.
    internal func setUIColor(for appearance: UserProperty) {
        let colors = AssociatedColors.getColors(for: appearance)
        
        navigator.view.backgroundColor = colors.mainColor
        view.backgroundColor = colors.mainColor
        //
        navigationController?.navigationBar.barTintColor = colors.mainColor
        navigationController?.navigationBar.tintColor = colors.textColor
        
        navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: colors.textColor]
    }
    
}

extension YabrReadiumEPUBViewController: UIPopoverPresentationControllerDelegate {
    // Prevent the popOver to be presented fullscreen on iPhones.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
    {
        return .none
    }
}


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

extension YabrReadiumEPUBViewController: ReaderFormatModuleDelegate {
    func presentOutline(of publication: Publication, delegate: OutlineTableViewControllerDelegate?, from viewController: UIViewController) {
        
    }
    
    func presentDRM(for publication: Publication, from viewController: UIViewController) {
        
    }
}

