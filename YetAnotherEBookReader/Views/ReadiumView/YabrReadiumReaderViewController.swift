//
//  YabrReadiumReaderViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import SafariServices
import UIKit
import SwiftUI
import ReadiumNavigator
import ReadiumShared
import ReadiumAdapterGCDWebServer
import SwiftSoup
import WebKit
import AVFoundation
import MediaPlayer
import RealmSwift


struct YabrReadiumEnvironment {
    let httpClient: HTTPClient
    let assetRetriever: AssetRetriever
    let httpServer: GCDHTTPServer
    let book: CalibreBook?
}

extension YabrReadiumReaderViewController: UIPopoverPresentationControllerDelegate {
    // Prevent the popOver to be presented fullscreen on iPhones.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return .none
    }
}

fileprivate extension Array where Element == ReadiumShared.Link {
    func firstDeep(withHREF href: String) -> ReadiumShared.Link? {
        return first {
            $0.href == href || URL(string: $0.href)?.path == href || $0.children.firstDeep(withHREF: href) != nil
        }
    }
    
    func firstDeep(withFRAGMENT fragment: String) -> ReadiumShared.Link? {
        return first {
            URL(string: $0.href)?.fragment == fragment || $0.children.firstDeep(withFRAGMENT: fragment) != nil
        }
    }
    
    func flattened() -> [ReadiumShared.Link] {
        var result: [ReadiumShared.Link] = []
        for link in self {
            result.append(link)
            result.append(contentsOf: link.children.flattened())
        }
        return result
    }
}


protocol YabrReadiumMetaSource {
    func yabrReadiumReadPosition(_ viewController: YabrReadiumReaderViewController, update: (Double, Double, [String: Any], String))
}

class YabrReadiumReaderViewController: 
    UIViewController, Loggable, NavigatorDelegate, VisualNavigatorDelegate, PDFNavigatorDelegate {

    let navigator: UIViewController & Navigator
    let publication: Publication
    let initialLocation: Locator?
    
    let environment: YabrReadiumEnvironment
    var popoverNavigationAnchor: UIBarButtonItem?
    var popoverUserconfigurationAnchor: UIBarButtonItem?

    var readiumMetaSource: YabrReadiumMetaSource? = nil
    
    var readiumPrefs: ReadiumPreferenceRealm?
    var prefsToken: NotificationToken?

    private(set) var stackView: UIStackView!
    private var stackViewTopConstraint: NSLayoutConstraint!
    
    private lazy var positionLabel = UILabel()
    
    private var volumeView: MPVolumeView?
    private var volumeObserver: NSKeyValueObservation?
    private var isHandlingVolumeChange = false
    private var lastRequestedVolume: Float?
    
    /// This regex matches any string with at least 2 consecutive letters (not limited to ASCII).
    /// It's used when evaluating whether to display the body of a noteref referrer as the note's title.
    /// I.e. a `*` or `1` would not be used as a title, but `on` or `好書` would.
    private static var noterefTitleRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "[\\p{Ll}\\p{Lu}\\p{Lt}\\p{Lo}]{2}")
    }()
    
    // MARK: - Navigation bar
    
    private var navigationBarHidden: Bool = true
    
    init(navigator: UIViewController & Navigator, publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        self.initialLocation = initialLocation
        self.navigator = navigator
        self.publication = publication
        self.environment = environment

        super.init(nibName: nil, bundle: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(voiceOverStatusDidChange), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
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
                    
                    if let epub = navigator as? EPUBNavigatorViewController {
                        newPrefs.update(from: epub.settings)
                    } else if let pdf = navigator as? PDFNavigatorViewController {
                        newPrefs.update(from: pdf.settings)
                    }
                    
                    try? realm.write {
                        realm.add(newPrefs)
                    }
                    self.readiumPrefs = newPrefs
                }
                
                // Initial vertical margin (Only in Paged Mode)
                let isScroll = self.readiumPrefs?.scroll ?? false
                let vMargin = isScroll ? 0 : CGFloat(self.readiumPrefs?.verticalMargin ?? 0.0)
                self.log(.debug, "Initial vMargin set to \(vMargin) (isScroll: \(isScroll))")
                navigator.additionalSafeAreaInsets = UIEdgeInsets(top: vMargin, left: 0, bottom: vMargin, right: 0)
                
                // Initial volume key paging setup
                self.setupVolumeKeyPaging(isEnabled: self.readiumPrefs?.volumeKeyPaging ?? false)
                
                if let prefs = self.readiumPrefs {
                    self.applyPreferences(prefs)
                }
                
                // Observe changes from SwiftUI
                self.prefsToken = self.readiumPrefs?.observe { [weak self] change in
                    guard let self = self, let prefs = self.readiumPrefs else { return }
                    if case .change = change {
                        self.applyPreferences(prefs)
                        
                        // Animate background color change for smooth theme transition
                        UIView.animate(withDuration: 0.3) {
                            self.view.backgroundColor = prefs.themeColor
                            self.updateNavigationBarTheme()
                            self.setNeedsStatusBarAppearanceUpdate()
                        }
                        
                        // React to volume key paging toggle
                        self.setupVolumeKeyPaging(isEnabled: prefs.volumeKeyPaging)
                        
                        // Apply vertical margin directly via additionalSafeAreaInsets
                        // Only applied in Paged Mode to prevent gaps between chapters in Scroll Mode.
                        let isScroll = prefs.scroll
                        let vMargin = isScroll ? 0 : CGFloat(prefs.verticalMargin)
                        self.log(.debug, "preference change detected, updating additionalSafeAreaInsets to \(vMargin) (isScroll: \(isScroll))")
                        self.navigator.additionalSafeAreaInsets = UIEdgeInsets(top: vMargin, left: 0, bottom: vMargin, right: 0)
                    }
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        prefsToken?.invalidate()
        teardownVolumeKeyPaging()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Ensure navigator background is clear so host view background shows through Safe Areas
        navigator.view.backgroundColor = .clear
        
        // Allow content to flow behind navigation bar
        self.edgesForExtendedLayout = .all
        self.extendedLayoutIncludesOpaqueBars = true
        
        view.backgroundColor = self.readiumPrefs?.themeColor ?? .white
      
        navigationItem.rightBarButtonItems = makeNavigationBarButtons()
        
        // Explicitly set initial state to ensure synchronization
        navigationBarHidden = true
        updateNavigationBar(animated: false)
        
        stackView = UIStackView(frame: view.bounds)
        stackView.distribution = .fill
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Pin stackView to view.topAnchor with a dynamic constraint to handle status bar vs nav bar
        stackViewTopConstraint = stackView.topAnchor.constraint(equalTo: view.topAnchor)
        
        NSLayoutConstraint.activate([
            isVoiceOverRunning ? accessibilityTopMargin : stackViewTopConstraint,
            stackView.rightAnchor.constraint(equalTo: view.rightAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.leftAnchor.constraint(equalTo: view.leftAnchor)
        ])

        addChild(navigator)
        stackView.addArrangedSubview(navigator.view)
        navigator.didMove(toParent: self)
        
        if isVoiceOverRunning {
            stackView.addArrangedSubview(accessibilityToolbar)
        }
        
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.font = .systemFont(ofSize: 12)
        positionLabel.textColor = .darkGray
        view.addSubview(positionLabel)
        NSLayoutConstraint.activate([
            positionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            positionLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
        
        updateNavigationBarTheme()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if !(readiumPrefs?.scroll ?? false), let margin = readiumPrefs?.verticalMargin {
            (navigator as? UIViewController)?.additionalSafeAreaInsets = UIEdgeInsets(top: margin, left: 0, bottom: margin, right: 0)
        }
        
        updateNavigationBarTheme()
        updateNavigationBar(animated: false)
        setupVolumeKeyPaging(isEnabled: readiumPrefs?.volumeKeyPaging ?? false)
        
        // Initial metadata and title sync
        if let location = navigator.currentLocation {
            updateMetadata(for: location)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        teardownVolumeKeyPaging()
        
        // Restore default navigation bar tint color to avoid leaking the theme
        navigationController?.navigationBar.tintColor = nil
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Calculate the effective top inset to avoid status bar but ignore navigation bar
        let statusBarHeight = view.window?.safeAreaInsets.top ?? view.safeAreaInsets.top
        
        // Update constraint to ensure content starts exactly below the system safe area inset (status bar)
        // This is only set if VoiceOver is NOT running (which uses its own top margin constraint).
        if !isVoiceOverRunning {
            if stackViewTopConstraint.constant != statusBarHeight {
                stackViewTopConstraint.constant = statusBarHeight
                view.setNeedsLayout()
            }
        }
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
            navBar.tintColor = (prefs.themeMode == 1) ? UIColor(red: 0.36, green: 0.15, blue: 0.25, alpha: 1.0) : textColor
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return (readiumPrefs?.themeMode == 2) ? .lightContent : .darkContent
    }

    func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons: [UIBarButtonItem] = []
        
        // User configuration button
        let settingsButton = UIBarButtonItem(image: UIImage(systemName: "textformat.size"), style: .plain, target: self, action: #selector(presentSettings))
        buttons.append(settingsButton)
        popoverUserconfigurationAnchor = settingsButton
        
        // Navigation panel button
        let tocButton = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(presentNavigationPanel))
        buttons.append(tocButton)
        popoverNavigationAnchor = tocButton
        
        return buttons
    }
    
    @objc func presentSettings() {
        guard let prefs = readiumPrefs else { return }
        
        let viewModel = YabrReaderSettingsViewModel(prefs: prefs, publication: self.publication, navigator: self.navigator)
        viewModel.onChanged = { [weak self] in
            self?.updateNavigationBarTheme()
            self?.setupVolumeKeyPaging(isEnabled: self?.readiumPrefs?.volumeKeyPaging ?? false)
        }
        
        let settingsView = YabrReaderSettingsView(model: viewModel)
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
    
    func applyPreferences(_ prefs: ReadiumPreferenceRealm) {
        if let epub = navigator as? EPUBNavigatorViewController {
            epub.submitPreferences(prefs.toEPUBPreferences())
        } else if let pdf = navigator as? PDFNavigatorViewController {
            pdf.submitPreferences(prefs.toPDFPreferences())
        }
    }
    
    func toggleNavigationBar() {
        navigationBarHidden = !navigationBarHidden
        updateNavigationBar()
    }
    
    private func updateNavigationBar(animated: Bool = true) {
        let hidden = navigationBarHidden && !isVoiceOverRunning
        navigationController?.setNavigationBarHidden(hidden, animated: animated)
        setNeedsStatusBarAppearanceUpdate()
    }
    
    func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
        log(.error, "ReadiumReaderViewController didFailToLoadResourceAt \(href.string) \(error)")
    }
    
    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        let safariVC = SFSafariViewController(url: url)
        present(safariVC, animated: true)
    }
    
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        log(.error, "ReadiumReaderViewController presentError \(error)")
    }
    
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        updateMetadata(for: locator)
    }
    
    private func updateMetadata(for locator: Locator) {
        positionLabel.text = {
            if let position = locator.locations.position {
                return "\(position) / \(self.publication.readingOrder.count)"
            } else {
                return ""
            }
        }()
        
        Task { [weak self] in
            guard let self = self else { return }
            var updatedReadingPosition = (Double(), Double(), [String: Any](), "")
            
            // Extract common metadata
            updatedReadingPosition.0 = locator.locations.progression ?? 0.0
            updatedReadingPosition.1 = locator.locations.totalProgression ?? 0.0
            
            // Format-specific calculations for pageNumber and maxPage
            if navigator is EPUBNavigatorViewController {
                if let index = self.publication.readingOrder.firstIndexWithHREF(locator.href) {
                    updatedReadingPosition.2["pageNumber"] = index + 1
                } else {
                    updatedReadingPosition.2["pageNumber"] = 1
                }
                updatedReadingPosition.2["maxPage"] = self.publication.readingOrder.count
                updatedReadingPosition.2["pageOffsetX"] = locator.locations.position
            } else if navigator is PDFNavigatorViewController {
                updatedReadingPosition.2["pageNumber"] = locator.locations.position
                let positionsResult = await self.publication.positionsByReadingOrder()
                updatedReadingPosition.2["maxPage"] = (try? positionsResult.get())?.first?.count ?? 1
                updatedReadingPosition.2["pageOffsetX"] = 0
            } else {
                // Default fallback (e.g. CBZ)
                updatedReadingPosition.2["pageNumber"] = locator.locations.position
                updatedReadingPosition.2["maxPage"] = self.publication.readingOrder.count
                updatedReadingPosition.2["pageOffsetX"] = 0
            }
            
            // Title resolution
            let tocResult = await self.publication.tableOfContents()
            let tableOfContents = (try? tocResult.get()) ?? []
            
            let currentTitle: String = {
                if let title = locator.title {
                    return title
                }
                
                // 1. Try finding by HREF (exact resource match)
                if !(self.navigator is PDFNavigatorViewController) {
                    if let tocLink = tableOfContents.firstDeep(withHREF: locator.href.string),
                       let tocTitle = tocLink.title {
                        return tocTitle
                    }

                    // 2. Try finding by Fragment (exact anchor match)
                    if let fragment = locator.locations.fragments.first,
                       let tocLink = tableOfContents.firstDeep(withFRAGMENT: fragment),
                       let tocTitle = tocLink.title {
                        return tocTitle
                    }
                }
                
                // 3. Try finding by Page Range (for PDF/CBZ or fixed-layout EPUB)
                if let locPageNumber = locator.locations.position,
                   let tocLink = tableOfContents.flattened().filter({ link in
                       guard let tocFragmentIndex = link.href.firstIndex(of: "#"),
                             let pageNumberValue = link.href[tocFragmentIndex...].split(separator: "=").last,
                             let pageNumber = Int(pageNumberValue)
                       else { return false }
                       return pageNumber <= locPageNumber
                   }).last,
                   let tocTitle = tocLink.title {
                    return tocTitle
                }
                
                // 4. Fallback to page number or unknown
                if let pageNumber = locator.locations.position {
                    return "Page \(pageNumber)"
                }
                return "Unknown Title"
            }()
            
            updatedReadingPosition.3 = currentTitle
            
            self.readiumMetaSource?.yabrReadiumReadPosition(self, update: updatedReadingPosition)
            
            DispatchQueue.main.async {
                self.navigationItem.title = currentTitle
            }
        }
    }
    
    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        let viewport = view.bounds
        let leftEdge = viewport.width * 0.2
        let rightEdge = viewport.width * 0.8
        
        let isScroll: Bool = {
            if let epub = navigator as? EPUBNavigatorViewController {
                return epub.settings.scroll
            }
            if let pdf = navigator as? PDFNavigatorViewController {
                return pdf.settings.scroll
            }
            return false
        }()
        
        if point.x < leftEdge && !isScroll {
            Task { await navigator.goLeft(options: .animated) }
        } else if point.x > rightEdge && !isScroll {
            Task { await navigator.goRight(options: .animated) }
        } else {
            toggleNavigationBar()
        }
    }
    
    func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        return nil
    }
    
    // MARK: - Volume Key Paging
    
    func handleVolumeKey(up: Bool) {
        // To be overridden by subclasses if specialized scrolling is needed.
        // Default implementation just goes forward/backward or left/right.
        
        let isRTL = self.publication.metadata.readingProgression == .rtl
        let visualNavigator = self.navigator as? VisualNavigator
        
        Task {
            if up {
                if isRTL {
                    await visualNavigator?.goRight(options: .animated)
                } else {
                    await visualNavigator?.goLeft(options: .animated)
                }
            } else {
                if isRTL {
                    await visualNavigator?.goLeft(options: .animated)
                } else {
                    await visualNavigator?.goRight(options: .animated)
                }
            }
        }
    }
    
    func setupVolumeKeyPaging(isEnabled: Bool) {
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
    
    @objc private func appDidBecomeActive() {
        guard viewIfLoaded?.window != nil else { return }
        if readiumPrefs?.volumeKeyPaging == true {
            log(.debug, "App became active, re-setting up volume key paging")
            teardownVolumeKeyPaging()
            setupVolumeKeyPaging(isEnabled: true)
        }
    }
    
    @objc private func appDidEnterBackground() {
        if readiumPrefs?.volumeKeyPaging == true {
            log(.debug, "App entered background, tearing down volume key paging")
            teardownVolumeKeyPaging()
        }
    }
    
    func teardownVolumeKeyPaging() {
        self.log(.debug, "Teardown called")
        volumeObserver?.invalidate()
        volumeObserver = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
    
    // MARK: - Accessibility
    
    private lazy var accessibilityToolbar: UIToolbar = {
        func makeItem(_ item: UIBarButtonItem.SystemItem, label: String? = nil, action: UIKit.Selector? = nil) -> UIBarButtonItem {
            let button = UIBarButtonItem(barButtonSystemItem: item, target: (action != nil) ? self : nil, action: action)
            button.accessibilityLabel = label
            return button
        }
        
        let toolbar = UIToolbar(frame: .zero)
        toolbar.items = [
            makeItem(.flexibleSpace),
            makeItem(.rewind, label: NSLocalizedString("reader_backward_a11y_label", comment: "Accessibility label to go backward in the publication"), action: #selector(goBackward)),
            makeItem(.flexibleSpace),
            makeItem(.fastForward, label: NSLocalizedString("reader_forward_a11y_label", comment: "Accessibility label to go forward in the publication"), action: #selector(goForward)),
            makeItem(.flexibleSpace),
        ]
        toolbar.isHidden = !UIAccessibility.isVoiceOverRunning
        toolbar.tintColor = UIColor.black
        return toolbar
    }()
    
    private var isVoiceOverRunning = UIAccessibility.isVoiceOverRunning
    
    private lazy var accessibilityTopMargin: NSLayoutConstraint = {
        return stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
    }()
    
    @objc private func voiceOverStatusDidChange() {
        let isRunning = UIAccessibility.isVoiceOverRunning
        // Avoids excessive settings refresh when the status didn't change.
        guard isVoiceOverRunning != isRunning else {
            return
        }
        isVoiceOverRunning = isRunning
        
        // Ensure constraints are mutually exclusive to avoid conflicts
        accessibilityTopMargin.isActive = isRunning
        stackViewTopConstraint.isActive = !isRunning
        
        accessibilityToolbar.isHidden = !isRunning
        
        if isRunning {
            stackView.addArrangedSubview(accessibilityToolbar)
        } else {
            stackView.removeArrangedSubview(accessibilityToolbar)
            accessibilityToolbar.removeFromSuperview()
        }
        
        updateNavigationBar()
    }
    
    @objc func goBackward() {
        Task { await navigator.goBackward(options: .animated) }
    }
    
    @objc func goForward() {
        Task { await navigator.goForward(options: .animated) }
    }
}
