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
import AVFoundation
import MediaPlayer
import WebKit

import ReadiumAdapterGCDWebServer

class YabrReadiumEPUBViewController: YabrReadiumReaderViewController {


    var popoverUserconfigurationAnchor: UIBarButtonItem?
    var popoverNavigationAnchor: UIBarButtonItem?
    
    private var preferences = EPUBPreferences()
    private var readiumPrefs: ReadiumPreferenceRealm?
    private var prefsToken: NotificationToken?
    
    private var volumeView: MPVolumeView?
    private var volumeObserver: NSKeyValueObservation?
    private var isHandlingVolumeChange = false
    private var lastRequestedVolume: Float?

    init(publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        // Set contentInset to zero to allow additionalSafeAreaInsets to fully control margins
        var config = EPUBNavigatorViewController.Configuration()
        config.contentInset = [
            .compact: (top: 0, bottom: 0),
            .regular: (top: 0, bottom: 0)
        ]
        
        let navigator = try! EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocation,
            config: config
        )

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
                
                // Initial vertical margin (Only in Paged Mode)
                let isScroll = self.readiumPrefs?.scroll ?? false
                let vMargin = isScroll ? 0 : CGFloat(self.readiumPrefs?.verticalMargin ?? 0.0)
                self.log(.debug, "Initial vMargin set to \(vMargin) (isScroll: \(isScroll))")
                navigator.additionalSafeAreaInsets = UIEdgeInsets(top: vMargin, left: 0, bottom: vMargin, right: 0)
                
                // Set initial background color to match theme
                self.view.backgroundColor = self.readiumPrefs?.themeColor ?? .white
                
                // Apply theme to Navigation Bar immediately in init
                self.updateNavigationBarTheme()
                
                // Initial volume key paging setup
                self.setupVolumeKeyPaging()
                
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
                        
                        // React to volume key paging toggle
                        self.setupVolumeKeyPaging()
                        
                        // Apply vertical margin directly via additionalSafeAreaInsets
                        // Only applied in Paged Mode to prevent gaps between chapters in Scroll Mode.
                        let isScroll = prefs.scroll
                        let vMargin = isScroll ? 0 : CGFloat(prefs.verticalMargin)
                        self.log(.debug, "preference change detected, updating additionalSafeAreaInsets to \(vMargin) (isScroll: \(isScroll))")
                        self.epubNavigator.additionalSafeAreaInsets = UIEdgeInsets(top: vMargin, left: 0, bottom: vMargin, right: 0)
                    }
                }
            }
        }
    }
    
    deinit {
        teardownVolumeKeyPaging()
        prefsToken?.invalidate()
    }
    
    var epubNavigator: EPUBNavigatorViewController {
        return navigator as! EPUBNavigatorViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Ensure navigator background is clear so host view background shows through Safe Areas
        navigator.view.backgroundColor = .clear
        
        updateNavigationBarTheme()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavigationBarTheme()
        setupVolumeKeyPaging()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        teardownVolumeKeyPaging()
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
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = prefs.themeColor.withAlphaComponent(0.85)
        
        let textColor: UIColor = (prefs.themeMode == 2) ? .white : .black
        appearance.titleTextAttributes = [.foregroundColor: textColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: textColor]
        
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
    
    private func getVerticalScrollViews(from view: UIView, into list: inout [WKWebView]) {
        if let webView = view as? WKWebView {
            list.append(webView)
        }
        for subview in view.subviews {
            getVerticalScrollViews(from: subview, into: &list)
        }
    }
    
    private func getActiveVerticalScrollView() -> UIScrollView? {
        var webViews = [WKWebView]()
        getVerticalScrollViews(from: self.navigator.view, into: &webViews)
        
        if webViews.isEmpty { return nil }
        if webViews.count == 1 { return webViews[0].scrollView }
        
        // If multiple exist (e.g. during transition), find the one most central to the container
        let containerBounds = self.navigator.view.bounds
        let containerCenter = CGPoint(x: containerBounds.midX, y: containerBounds.midY)
        
        return webViews.sorted { (wv1, wv2) -> Bool in
            let frame1 = wv1.convert(wv1.bounds, to: self.navigator.view)
            let frame2 = wv2.convert(wv2.bounds, to: self.navigator.view)
            let dist1 = pow(frame1.midX - containerCenter.x, 2) + pow(frame1.midY - containerCenter.y, 2)
            let dist2 = pow(frame2.midX - containerCenter.x, 2) + pow(frame2.midY - containerCenter.y, 2)
            return dist1 < dist2
        }.first?.scrollView
    }
    
    private func handleVolumeKey(up: Bool) {
        let isScroll = self.preferences.scroll ?? false
        let isRTL = self.preferences.readingProgression == .rtl
        
        if isScroll {
            guard let scrollView = getActiveVerticalScrollView() else {
                self.log(.debug, "No active scroll view found, falling back to jump")
                Task {
                    if up { await self.epubNavigator.goBackward(options: .animated) }
                    else { await self.epubNavigator.goForward(options: .animated) }
                }
                return
            }
            
            let offset = scrollView.contentOffset
            let viewHeight = scrollView.bounds.height
            let contentHeight = scrollView.contentSize.height
            let scrollAmount = max(0, viewHeight - 80)
            
            if up {
                if offset.y <= 0 {
                    self.log(.debug, "At top, jumping backward")
                    Task { await self.epubNavigator.goBackward(options: .animated) }
                } else {
                    let newY = max(0, offset.y - scrollAmount)
                    self.log(.debug, "Scrolling up to \(newY)")
                    scrollView.setContentOffset(CGPoint(x: offset.x, y: newY), animated: true)
                }
            } else {
                let maxOffsetY = max(0, contentHeight - viewHeight)
                if offset.y >= maxOffsetY - 1 { // 1pt tolerance
                    self.log(.debug, "At bottom, jumping forward")
                    Task { await self.epubNavigator.goForward(options: .animated) }
                } else {
                    let newY = min(maxOffsetY, offset.y + scrollAmount)
                    self.log(.debug, "Scrolling down to \(newY)")
                    scrollView.setContentOffset(CGPoint(x: offset.x, y: newY), animated: true)
                }
            }
        } else {
            Task {
                if up {
                    if isRTL {
                        await self.epubNavigator.goRight(options: .animated)
                    } else {
                        await self.epubNavigator.goLeft(options: .animated)
                    }
                } else {
                    if isRTL {
                        await self.epubNavigator.goLeft(options: .animated)
                    } else {
                        await self.epubNavigator.goRight(options: .animated)
                    }
                }
            }
        }
    }
    
    func setupVolumeKeyPaging() {
        let isEnabled = readiumPrefs?.volumeKeyPaging ?? false
        
        guard isEnabled else {
            teardownVolumeKeyPaging()
            return
        }
        
        // Ensure MPVolumeView is in hierarchy to suppress system HUD and capture events
        if volumeView == nil {
            let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            view.clipsToBounds = true
            view.alpha = 0.01
            view.isUserInteractionEnabled = false
            self.view.addSubview(view)
            self.volumeView = view
            
            // Force layout to instantiate the UISlider quickly
            view.setNeedsLayout()
            view.layoutIfNeeded()
            self.log(.debug, "MPVolumeView initialized")
        }
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            self.log(.debug, "AVAudioSession activated")
        } catch {
            self.log(.error, "Failed to activate audio session: \(error)")
        }
        
        setSystemVolume(0.5)
        
        if volumeObserver == nil {
            volumeObserver = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] session, change in
                DispatchQueue.main.async {
                    guard let self = self,
                          let newVol = change.newValue,
                          let oldVol = change.oldValue else { return }
                    
                    self.log(.debug, "RAW Change detected \(oldVol) -> \(newVol)")
                    
                    // 1. Exact Programmatic Match: Ignore completely
                    if let lastReq = self.lastRequestedVolume, abs(newVol - lastReq) < 0.01 {
                        self.log(.debug, "Programmatic change handled (\(newVol))")
                        self.lastRequestedVolume = nil
                        return
                    }
                    
                    // 2. Determine direction
                    let isUp: Bool
                    
                    // If there's a massive jump (>0.15) while a request is pending, our programmatic setting
                    // was combined with a physical key press. Compare against the TARGET, not the old volume.
                    if let lastReq = self.lastRequestedVolume, abs(newVol - oldVol) > 0.15 {
                        self.log(.debug, "Massive jump. Target: \(lastReq), Actual: \(newVol)")
                        // If the actual volume fell short of the 0.5 target, they pressed DOWN.
                        // If it overshot the 0.5 target, they pressed UP.
                        isUp = newVol > lastReq
                    } else {
                        // Normal user step
                        isUp = newVol > oldVol
                    }
                    
                    // 3. Clear pending request flags
                    self.lastRequestedVolume = nil
                    
                    // 4. Rate Limiting
                    if self.isHandlingVolumeChange { 
                        self.log(.debug, "Busy, skipping event")
                        return 
                    }
                    self.isHandlingVolumeChange = true
                    
                    // 5. Process
                    self.log(.debug, "USER EVENT! UP=\(isUp) (\(oldVol) -> \(newVol))")
                    self.handleVolumeKey(up: isUp)
                    
                    // 6. Reset to baseline 0.5
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.setSystemVolume(0.5)
                        self.isHandlingVolumeChange = false
                    }
                }
            }
            self.log(.debug, "Observer attached")
        }
    }
    
    func teardownVolumeKeyPaging() {
        self.log(.debug, "Teardown called")
        volumeObserver?.invalidate()
        volumeObserver = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
    }
    
    private func setSystemVolume(_ volume: Float, retryCount: Int = 0) {
        guard let volumeView = volumeView else { return }
        self.lastRequestedVolume = volume
        
        DispatchQueue.main.async {
            func findSlider(in view: UIView) -> UISlider? {
                if let slider = view as? UISlider { return slider }
                for subview in view.subviews {
                    if let found = findSlider(in: subview) { return found }
                }
                return nil
            }
            
            if let slider = findSlider(in: volumeView) {
                slider.value = volume
            } else if retryCount < 10 {
                // Slider might not be ready yet due to lazy loading of MPVolumeView subviews
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.setSystemVolume(volume, retryCount: retryCount + 1)
                }
            }
        }
    }
    
    override func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        super.navigator(navigator, locationDidChange: locator)
        
        self.log(.debug, "locationDidChange: \(locator)")
        
        Task { [weak self] in
            guard let self = self else { return }
            var updatedReadingPosition = (Double(), Double(), [String: Any](), "")
            
            if let index = self.publication.readingOrder.firstIndexWithHREF(locator.href) {
                updatedReadingPosition.2["pageNumber"] = index + 1
            } else {
                updatedReadingPosition.2["pageNumber"] = 1
            }
            updatedReadingPosition.2["maxPage"] = self.publication.readingOrder.count
            updatedReadingPosition.2["pageOffsetX"] = locator.locations.position
            
            updatedReadingPosition.0 = locator.locations.progression ?? 0.0
            updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
            
            let tocResult = await self.publication.tableOfContents()
            let tableOfContents = (try? tocResult.get()) ?? []
            
            if let title = locator.title {
                updatedReadingPosition.3 = title
            } else if let tocLink = tableOfContents.firstDeep(withHREF: locator.href.string),
                      let tocTitle = tocLink.title {
                updatedReadingPosition.3 = tocTitle
            } else {
                updatedReadingPosition.3 = "Unknown Chapter"
            }
            
            self.readiumMetaSource?.yabrReadiumReadPosition(self, update: updatedReadingPosition)
        }
    }
    
    override func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        let prefs = readiumPrefs
        let isScroll = prefs?.scroll ?? false
        
        if isScroll {
            return nil
        }
        
        let safeArea = self.view.window?.safeAreaInsets ?? .zero
        let additional = self.epubNavigator.additionalSafeAreaInsets
        
        let inset = UIEdgeInsets(
            top: safeArea.top + additional.top,
            left: safeArea.left + additional.left,
            bottom: safeArea.bottom + additional.bottom,
            right: safeArea.right + additional.right
        )
        self.log(.debug, "navigatorContentInset called, additionalTop=\(additional.top), returning: \(inset)")
        return inset
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
