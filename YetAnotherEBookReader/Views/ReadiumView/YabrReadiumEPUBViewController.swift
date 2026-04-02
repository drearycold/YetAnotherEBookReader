//
//  YabrReadiumEPUBViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/29.
//

import Foundation
import UIKit
import SwiftUI
import RealmSwift
import ReadiumShared
import ReadiumNavigator

import ReadiumAdapterGCDWebServer

class YabrReadiumEPUBViewController: YabrReadiumReaderViewController {


    var popoverUserconfigurationAnchor: UIBarButtonItem?
    var popoverNavigationAnchor: UIBarButtonItem?
    
    private var preferences = EPUBPreferences()
    private var readiumPrefs: ReadiumPreferenceRealm?
    private var prefsToken: NotificationToken?

    init(publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        let navigator = try! EPUBNavigatorViewController(publication: publication, initialLocation: initialLocation)

        super.init(navigator: navigator, publication: publication, initialLocation: initialLocation, environment: environment)

        navigator.delegate = self
        
        // Initialize preference store and load preferences
        if let book = environment.book {
            let config = BookAnnotation.getBookPreferenceServerConfig(book.library.server)
            if let realm = try? Realm(configuration: config) {
                let bookId = book.readPos.bookPrefId
                if let savedPrefs = realm.object(ofType: ReadiumPreferenceRealm.self, forPrimaryKey: bookId) {
                    self.readiumPrefs = savedPrefs
                } else {
                    let newPrefs = ReadiumPreferenceRealm()
                    newPrefs.id = bookId
                    newPrefs.update(from: navigator.settings)
                    try? realm.write {
                        realm.add(newPrefs)
                    }
                    self.readiumPrefs = newPrefs
                }
                
                self.preferences = self.readiumPrefs!.toEPUBPreferences()
                navigator.submitPreferences(self.preferences)
                
                // Set initial background color to match theme
                self.view.backgroundColor = self.readiumPrefs?.themeColor ?? .white
                
                // Apply theme to Navigation Bar immediately in init
                self.updateNavigationBarTheme()
                
                // Observe changes from SwiftUI
                self.prefsToken = self.readiumPrefs?.observe { [weak self] change in
                    guard let self = self, let prefs = self.readiumPrefs else { return }
                    if case .change = change {
                        self.preferences = prefs.toEPUBPreferences()
                        self.epubNavigator.submitPreferences(self.preferences)
                        
                        // Animate background color change for smooth theme transition
                        UIView.animate(withDuration: 0.3) {
                            self.view.backgroundColor = prefs.themeColor
                            self.updateNavigationBarTheme()
                            self.setNeedsStatusBarAppearanceUpdate()
                        }
                    }
                }
            }
        }
    }
    
    deinit {
        prefsToken?.invalidate()
    }
    
    var epubNavigator: EPUBNavigatorViewController {
        return navigator as! EPUBNavigatorViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Ensure navigator background is clear so host view background shows through Safe Areas
        navigator.view.backgroundColor = .clear
        
        // Reinforce theme on load
        updateNavigationBarTheme()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavigationBarTheme()
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
        
        // Navigation panel button
        let tocButton = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(presentNavigationPanel))
        buttons.insert(tocButton, at: 1)
        popoverNavigationAnchor = tocButton

        return buttons
    }
    
    @objc func presentSettings() {
        guard let prefs = readiumPrefs else { return }
        
        let settingsView = YabrReaderSettingsView(prefs: prefs)
        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.modalPresentationStyle = .popover
        hostingController.popoverPresentationController?.barButtonItem = popoverUserconfigurationAnchor
        hostingController.popoverPresentationController?.delegate = self
        
        present(hostingController, animated: true)
    }
    
    @objc func presentNavigationPanel() {
        let vm = YabrReaderNavigationViewModel(publication: self.publication)
        vm.loadAnnotations(book: environment.book)
        
        let navigationView = YabrReaderNavigationView(viewModel: vm)
        let hostingController = UIHostingController(rootView: navigationView)
        hostingController.modalPresentationStyle = .popover
        hostingController.popoverPresentationController?.barButtonItem = popoverNavigationAnchor
        hostingController.popoverPresentationController?.delegate = self
        
        vm.onNavigateToLink = { [weak self, weak hostingController] link in
            hostingController?.dismiss(animated: true) {
                Task { [weak self] in
                    await self?.navigator.go(to: link)
                }
            }
        }
        
        vm.onNavigateToLocator = { [weak self, weak hostingController] locator in
            hostingController?.dismiss(animated: true) {
                Task { [weak self] in
                    await self?.navigator.go(to: locator)
                }
            }
        }
        
        present(hostingController, animated: true)
    }
    
    func updateNavigationBarTheme() {
        guard let prefs = readiumPrefs else { return }
        
        let appearance = UINavigationBarAppearance()
        // Use default or transparent background to allow semi-transparent effect
        appearance.configureWithDefaultBackground()
        // Set semi-transparent theme color
        appearance.backgroundColor = prefs.themeColor.withAlphaComponent(0.85)
        
        let textColor: UIColor = (prefs.themeMode == 2) ? .white : .black
        appearance.titleTextAttributes = [.foregroundColor: textColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: textColor]
        
        // Apply to navigationItem appearances
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        
        if let navBar = navigationController?.navigationBar {
            navBar.tintColor = (prefs.themeMode == 1) ? UIColor(red: 0.36, green: 0.25, blue: 0.15, alpha: 1.0) : textColor
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return (readiumPrefs?.themeMode == 2) ? .lightContent : .darkContent
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

// MARK: - ReadiumPreferenceRealm Extensions

extension ReadiumPreferenceRealm {
    
    var themeColor: UIColor {
        switch themeMode {
        case 1: // Sepia
            return UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1.0) // #FAF4E8
        case 2: // Dark
            return .black
        default: // Light
            return .white
        }
    }

    func toEPUBPreferences() -> EPUBPreferences {
        EPUBPreferences(
            columnCount: self.columnCount == 0 ? .auto : (self.columnCount == 1 ? .one : .two),
            fontFamily: self.fontFamily == "Original" ? nil : FontFamily(rawValue: self.fontFamily),
            fontSize: self.fontSizePercentage / 100.0,
            fontWeight: self.fontWeight,
            hyphens: self.hyphens,
            imageFilter: self.imageFilter == 0 ? nil : (self.imageFilter == 1 ? .darken : .invert),
            letterSpacing: self.letterSpacing,
            lineHeight: self.lineHeight,
            pageMargins: self.pageMargins,
            paragraphIndent: self.paragraphIndent,
            paragraphSpacing: self.paragraphSpacing,
            publisherStyles: self.publisherStyles,
            scroll: self.scroll,
            textAlign: {
                switch self.textAlign {
                case 1: return .start
                case 2: return .left
                case 3: return .right
                case 4: return .justify
                default: return nil
                }
            }(),
            textNormalization: self.textNormalization,
            theme: {
                switch self.themeMode {
                case 1: return .sepia
                case 2: return .dark
                default: return .light
                }
            }(),
            typeScale: self.typeScale,
            wordSpacing: self.wordSpacing
        )
    }
    
    func update(from settings: EPUBSettings) {
        switch settings.theme {
        case .light: self.themeMode = 0
        case .sepia: self.themeMode = 1
        case .dark: self.themeMode = 2
        }
        
        self.fontSizePercentage = settings.fontSize * 100.0
        
        if let fontFamily = settings.fontFamily {
            self.fontFamily = fontFamily.rawValue
        } else {
            self.fontFamily = "Original"
        }
        
        self.lineHeight = settings.lineHeight ?? 1.2
        self.pageMargins = settings.pageMargins
        self.publisherStyles = settings.publisherStyles
        self.scroll = settings.scroll
        
        switch settings.textAlign {
        case .start: self.textAlign = 1
        case .left: self.textAlign = 2
        case .right: self.textAlign = 3
        case .justify: self.textAlign = 4
        default: self.textAlign = 0
        }
        
        switch settings.columnCount {
        case .auto: self.columnCount = 0
        case .one: self.columnCount = 1
        case .two: self.columnCount = 2
        default: self.columnCount = 0
        }
        
        self.fontWeight = settings.fontWeight ?? 1.0
        self.letterSpacing = settings.letterSpacing ?? 0.0
        self.wordSpacing = settings.wordSpacing ?? 0.0
        self.hyphens = settings.hyphens ?? false
        
        if let filter = settings.imageFilter {
            switch filter {
            case .darken: self.imageFilter = 1
            case .invert: self.imageFilter = 2
            @unknown default: self.imageFilter = 0
            }
        } else {
            self.imageFilter = 0
        }
        
        self.textNormalization = settings.textNormalization
        self.typeScale = settings.typeScale ?? 1.2
        self.paragraphIndent = settings.paragraphIndent ?? 0.0
        self.paragraphSpacing = settings.paragraphSpacing ?? 0.0
    }
}
