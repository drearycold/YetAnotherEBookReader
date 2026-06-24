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


struct YabrReadiumEnvironment {
    let httpClient: HTTPClient
    let assetRetriever: AssetRetriever
    let httpServer: GCDHTTPServer
    let book: CalibreBook?
    let readerPreferenceRepository: ReaderPreferenceRepositoryProtocol
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


class YabrReadiumReaderViewController: 
    UIViewController, Loggable, NavigatorDelegate, VisualNavigatorDelegate, PDFNavigatorDelegate {

    let navigator: UIViewController & Navigator
    let publication: Publication
    let initialLocation: Locator?
    
    let environment: YabrReadiumEnvironment
    var popoverNavigationAnchor: UIBarButtonItem?
    var popoverUserconfigurationAnchor: UIBarButtonItem?

    weak var readerEngineDelegate: ReaderEngineDelegate? = nil
    
    var readiumPreferences: ReadiumPreferenceValue?

    private(set) var stackView: UIStackView!
    private var stackViewTopConstraint: NSLayoutConstraint!
    
    private lazy var positionLabel = UILabel()
    
    private var volumeView: MPVolumeView?
    private var volumeObserver: NSKeyValueObservation?
    private let pagingCoordinator = ReadiumVolumeKeyPagingCoordinator()
    private var pendingBaselineVolume: Float?
    
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
        
        if let book = environment.book {
            var initialPreferences = ReadiumPreferenceValue(id: book.bookPrefId)
            if let epub = navigator as? EPUBNavigatorViewController {
                initialPreferences.update(from: epub.settings)
            } else if let pdf = navigator as? PDFNavigatorViewController {
                initialPreferences.update(from: pdf.settings)
            }

            if let savedPreferences = environment.readerPreferenceRepository.loadReadiumPreferences(for: book) {
                initialPreferences = savedPreferences
            }

            self.applyReadiumPreferences(initialPreferences)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
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
        
        view.backgroundColor = self.readiumPreferences?.themeColor ?? .white
        
        stackView = UIStackView(frame: view.bounds)
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.alignment = .fill
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        let topAnchor = stackView.topAnchor.constraint(equalTo: view.topAnchor)
        stackViewTopConstraint = topAnchor
        
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
        
        // Adds a label displaying the current page/chapter progress in accessibility mode
        positionLabel.accessibilityIdentifier = "AccessibilityPositionLabel"
        positionLabel.isAccessibilityElement = true
        positionLabel.font = .preferredFont(forTextStyle: .footnote)
        positionLabel.numberOfLines = 0
        positionLabel.textAlignment = .center
        positionLabel.textColor = .label
        positionLabel.isHidden = true
        stackView.addArrangedSubview(positionLabel)
        
        setupUserInterface()
        
        // Explicitly set initial state to ensure synchronization
        navigationBarHidden = true
        updateNavigationBar(animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if !(readiumPreferences?.scroll ?? false), let margin = readiumPreferences?.verticalMargin {
            navigator.additionalSafeAreaInsets = UIEdgeInsets(top: CGFloat(margin), left: 0, bottom: CGFloat(margin), right: 0)
        } else {
            navigator.additionalSafeAreaInsets = .zero
        }
        
        updateNavigationBarTheme()
        updateNavigationBar(animated: false)
        setupVolumeKeyPaging(isEnabled: readiumPreferences?.volumeKeyPaging ?? false)
        
        // Initial metadata and title sync
        if let location = navigator.currentLocation {
            updateMetadata(for: location)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        teardownVolumeKeyPaging()
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
        
        if pendingBaselineVolume != nil {
            attemptSettingPendingBaselineVolume()
        }
    }
    
    func setupUserInterface() {
        navigationItem.rightBarButtonItems = makeNavigationBarButtons()
        
        updateNavigationBarTheme()
    }
    
    private func updateNavigationBarTheme() {
        guard let prefs = readiumPreferences else { return }
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = prefs.themeColor
        
        let titleColor = (prefs.themeMode == 2) ? UIColor.white : UIColor.black
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]
        
        navigationController?.navigationBar.tintColor = (prefs.themeMode == 2) ? .white : nil
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return (readiumPreferences?.themeMode == 2) ? .lightContent : .darkContent
    }

    func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons: [UIBarButtonItem] = []
        
        // Settings panel button
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
        guard let preferences = readiumPreferences else { return }
        
        let viewModel = YabrReaderSettingsViewModel(
            preferences: preferences,
            publication: self.publication,
            navigator: self.navigator
        ) { [weak self] updatedPreferences in
            guard let self = self else { return }
            self.applyReadiumPreferences(updatedPreferences)
            if let book = self.environment.book {
                self.environment.readerPreferenceRepository.saveReadiumPreferences(updatedPreferences, for: book)
            }
            self.readerEngineDelegate?.readerEngine(self, didUpdatePreferences: updatedPreferences.toReaderEnginePreferences())
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
    
    func applyPreferences(_ prefs: ReadiumPreferenceValue) {
        if let epub = navigator as? EPUBNavigatorViewController {
            epub.submitPreferences(prefs.toEPUBPreferences())
        } else if let pdf = navigator as? PDFNavigatorViewController {
            pdf.submitPreferences(prefs.toPDFPreferences())
        }
    }

    func applyReadiumPreferences(_ preferences: ReadiumPreferenceValue) {
        self.readiumPreferences = preferences
        self.applyPreferences(preferences)

        let isScroll = preferences.scroll
        let verticalMargin = isScroll ? 0 : CGFloat(preferences.verticalMargin)
        self.log(.debug, "Applying vMargin \(verticalMargin) (isScroll: \(isScroll))")
        navigator.additionalSafeAreaInsets = UIEdgeInsets(top: verticalMargin, left: 0, bottom: verticalMargin, right: 0)
        view.backgroundColor = preferences.themeColor
        setupVolumeKeyPaging(isEnabled: preferences.volumeKeyPaging)
        updateNavigationBarTheme()
        setNeedsStatusBarAppearanceUpdate()
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
            
            var pageNumber = 1
            var maxPage = 1
            var pageOffsetX = 0
            
            // Format-specific calculations for pageNumber and maxPage
            if self.navigator is EPUBNavigatorViewController {
                if let index = self.publication.readingOrder.firstIndexWithHREF(locator.href) {
                    pageNumber = index + 1
                } else {
                    pageNumber = 1
                }
                maxPage = self.publication.readingOrder.count
                pageOffsetX = locator.locations.position ?? 0
            } else if self.navigator is PDFNavigatorViewController {
                pageNumber = locator.locations.position ?? 1
                let positionsResult = await self.publication.positionsByReadingOrder()
                maxPage = (try? positionsResult.get())?.first?.count ?? 1
                pageOffsetX = 0
            } else {
                // Default fallback (e.g. CBZ)
                pageNumber = locator.locations.position ?? 1
                maxPage = self.publication.readingOrder.count
                pageOffsetX = 0
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
            
            let enginePos = ReaderEnginePosition(
                pageNumber: pageNumber,
                maxPage: maxPage,
                pageOffsetX: pageOffsetX,
                pageOffsetY: 0,
                bookProgress: (locator.locations.totalProgression ?? 0.0) * 100,
                chapterProgress: (locator.locations.progression ?? 0.0) * 100,
                chapterName: currentTitle,
                cfi: locator.locations.fragments.first
            )
            
            self.readerEngineDelegate?.readerEngine(self, didUpdatePosition: enginePos)
            
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
    
    func performVolumeKeyPage(up: Bool) async {
        // To be overridden by subclasses if specialized scrolling is needed.
        // Default implementation just goes forward/backward or left/right.
        
        let isRTL = self.publication.metadata.readingProgression == .rtl
        let visualNavigator = self.navigator as? VisualNavigator
        
        if up {
            if isRTL {
                _ = await visualNavigator?.goRight(options: .animated)
            } else {
                _ = await visualNavigator?.goLeft(options: .animated)
            }
        } else {
            if isRTL {
                _ = await visualNavigator?.goLeft(options: .animated)
            } else {
                _ = await visualNavigator?.goRight(options: .animated)
            }
        }
    }
    
    func setupVolumeKeyPaging(isEnabled: Bool) {
        guard isEnabled else {
            teardownVolumeKeyPaging()
            return
        }
        
        if volumeObserver != nil && volumeView != nil {
            self.log(.debug, "Volume key paging is already active, skipping setup")
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
        
        pendingBaselineVolume = 0.5
        attemptSettingPendingBaselineVolume()
        
        if volumeObserver == nil {
            volumeObserver = session.observe(\.outputVolume, options: [.new, .old]) { [weak self] session, change in
                DispatchQueue.main.async {
                    guard let self = self,
                          let newVol = change.newValue,
                          let oldVol = change.oldValue else { return }
                    
                    self.log(.debug, "RAW Change detected \(oldVol) -> \(newVol)")
                    
                    let resolution = self.pagingCoordinator.handleVolumeChange(newVolume: newVol, oldVolume: oldVol)
                    
                    switch resolution {
                    case .ignoreProgrammatic:
                        self.log(.debug, "Programmatic change handled (\(newVol))")
                        
                    case .ignoreBusy:
                        self.log(.debug, "Busy, skipping event")
                        
                    case .pageUp, .pageDown:
                        let isUp = (resolution == .pageUp)
                        self.log(.debug, "USER EVENT! UP=\(isUp) (\(oldVol) -> \(newVol))")
                        
                        Task { @MainActor in
                            await self.performVolumeKeyPage(up: isUp)
                            self.setSystemVolume(0.5)
                            self.pagingCoordinator.unlock()
                        }
                    }
                }
            }
            self.log(.debug, "Observer attached")
        }
    }
    
    @objc private func appDidBecomeActive() {
        guard viewIfLoaded?.window != nil else { return }
        if readiumPreferences?.volumeKeyPaging == true {
            log(.debug, "App became active, re-setting up volume key paging")
            teardownVolumeKeyPaging()
            setupVolumeKeyPaging(isEnabled: true)
        }
    }
    
    @objc private func appDidEnterBackground() {
        if readiumPreferences?.volumeKeyPaging == true {
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
        pendingBaselineVolume = nil
        pagingCoordinator.reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func attemptSettingPendingBaselineVolume() {
        guard let pending = pendingBaselineVolume, let volumeView = volumeView else { return }
        if let slider = ReadiumVolumeKeyPagingCoordinator.findVolumeSlider(in: volumeView) {
            self.log(.debug, "Volume slider found, applying baseline volume \(pending)")
            self.pagingCoordinator.requestVolumeChange(to: pending)
            slider.value = pending
            pendingBaselineVolume = nil
        } else {
            self.log(.debug, "Volume slider not ready yet")
        }
    }
    
    private func setSystemVolume(_ volume: Float) {
        guard let volumeView = volumeView else { return }
        self.pagingCoordinator.requestVolumeChange(to: volume)
        
        if let slider = ReadiumVolumeKeyPagingCoordinator.findVolumeSlider(in: volumeView) {
            slider.value = volume
        } else {
            self.log(.warning, "Could not set system volume: volume slider not found")
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

extension YabrReadiumReaderViewController: ReaderEngineController {
    func applyPreferences(_ preferences: ReaderEnginePreferences) {
        var updatedPreferences = self.readiumPreferences ?? ReadiumPreferenceValue()
        updatedPreferences.apply(preferences)
        applyReadiumPreferences(updatedPreferences)
    }
    
    func applyHighlights(_ highlights: [ReaderEngineHighlight]) {
        // Readium engine highlight rendering is not yet implemented in the UI layer
    }
}
