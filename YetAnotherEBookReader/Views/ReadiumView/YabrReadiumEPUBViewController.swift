//
//  YabrReadiumEPUBViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/29.
//

import Foundation
import UIKit
import SwiftUI
import ReadiumShared
import ReadiumNavigator

import ReadiumAdapterGCDWebServer

class YabrReadiumEPUBViewController: YabrReadiumReaderViewController {


    var popoverUserconfigurationAnchor: UIBarButtonItem?
    
    private var preferences = EPUBPreferences()
    private var preferenceStore: ReadiumPreferenceStore?

    init(publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        let navigator = try! EPUBNavigatorViewController(publication: publication, initialLocation: initialLocation)

        super.init(navigator: navigator, publication: publication, initialLocation: initialLocation, environment: environment)

        navigator.delegate = self
        
        // Initialize preference store and load preferences
        if let book = environment.book {
            let store = ReadiumPreferenceStore(server: book.library.server)
            self.preferenceStore = store
            
            if let savedPrefs = store.load(id: book.readPos.bookPrefId) {
                // Apply saved preferences to initial state
                self.preferences = EPUBPreferences(
                    columnCount: savedPrefs.columnCount == 0 ? .auto : (savedPrefs.columnCount == 1 ? .one : .two),
                    fontFamily: savedPrefs.fontFamily == "Original" ? nil : FontFamily(rawValue: savedPrefs.fontFamily),
                    fontSize: savedPrefs.fontSizePercentage / 100.0,
                    fontWeight: savedPrefs.fontWeight,
                    hyphens: savedPrefs.hyphens,
                    imageFilter: savedPrefs.imageFilter == 0 ? nil : (savedPrefs.imageFilter == 1 ? .darken : .invert),
                    letterSpacing: savedPrefs.letterSpacing,
                    lineHeight: savedPrefs.lineHeight,
                    pageMargins: savedPrefs.pageMargins,
                    paragraphIndent: savedPrefs.paragraphIndent,
                    paragraphSpacing: savedPrefs.paragraphSpacing,
                    publisherStyles: savedPrefs.publisherStyles,
                    scroll: savedPrefs.scroll,
                    textAlign: {
                        switch savedPrefs.textAlign {
                        case 1: return .start
                        case 2: return .left
                        case 3: return .right
                        case 4: return .justify
                        default: return nil
                        }
                    }(),
                    textNormalization: savedPrefs.textNormalization,
                    theme: {
                        switch savedPrefs.themeMode {
                        case 1: return .sepia
                        case 2: return .dark
                        default: return .light
                        }
                    }(),
                    typeScale: savedPrefs.typeScale,
                    wordSpacing: savedPrefs.wordSpacing
                )
                
                // Submit loaded preferences to navigator
                navigator.submitPreferences(self.preferences)
            } else {
                // Initialize preferences from current settings if no saved ones
                self.preferences = EPUBPreferences(
                    backgroundColor: navigator.settings.backgroundColor,
                    columnCount: navigator.settings.columnCount,
                    fontFamily: navigator.settings.fontFamily,
                    fontSize: navigator.settings.fontSize,
                    fontWeight: navigator.settings.fontWeight,
                    hyphens: navigator.settings.hyphens,
                    imageFilter: navigator.settings.imageFilter,
                    language: navigator.settings.language,
                    letterSpacing: navigator.settings.letterSpacing,
                    ligatures: navigator.settings.ligatures,
                    lineHeight: navigator.settings.lineHeight,
                    offsetFirstPage: navigator.settings.offsetFirstPage,
                    pageMargins: navigator.settings.pageMargins,
                    paragraphIndent: navigator.settings.paragraphIndent,
                    paragraphSpacing: navigator.settings.paragraphSpacing,
                    publisherStyles: navigator.settings.publisherStyles,
                    readingProgression: navigator.settings.readingProgression,
                    scroll: navigator.settings.scroll,
                    spread: navigator.settings.spread,
                    textAlign: navigator.settings.textAlign,
                    textColor: navigator.settings.textColor,
                    textNormalization: navigator.settings.textNormalization,
                    theme: navigator.settings.theme,
                    typeScale: navigator.settings.typeScale,
                    verticalText: navigator.settings.verticalText,
                    wordSpacing: navigator.settings.wordSpacing
                )
            }
        }
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
        let settingsButton = UIBarButtonItem(image: UIImage(systemName: "textformat.size"), style: .plain, target: self, action: #selector(presentSettings))
        buttons.insert(settingsButton, at: 0)
        popoverUserconfigurationAnchor = settingsButton

        return buttons
    }
    
    @objc func presentSettings() {
        let vm = YabrReaderSettingsViewModel(
            engineType: .readium,
            readiumPrefs: self.preferences,
            readiumMetadata: self.publication.metadata
        )
        vm.onReadiumPreferencesSubmit = { [weak self, weak vm] newPrefs in
            guard let self = self, let vm = vm else { return }
            self.preferences = newPrefs
            self.epubNavigator.submitPreferences(newPrefs)
            
            // Save to persistence
            if let book = self.environment.book {
                self.preferenceStore?.save(id: book.readPos.bookPrefId, from: vm)
            }
        }
        
        let settingsView = YabrReaderSettingsView(viewModel: vm)
        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.modalPresentationStyle = .popover
        hostingController.popoverPresentationController?.barButtonItem = popoverUserconfigurationAnchor
        hostingController.popoverPresentationController?.delegate = self
        
        present(hostingController, animated: true)
    }
    
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

fileprivate extension Array where Element == ReadiumShared.Link {
    func firstDeep(withHREF href: String) -> ReadiumShared.Link? {
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
