//
//  YabrReadiumReaderViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import SafariServices
import UIKit
import ReadiumNavigator
import ReadiumShared
import ReadiumAdapterGCDWebServer
import SwiftSoup
import WebKit


struct YabrReadiumEnvironment {
    let httpClient: HTTPClient
    let assetRetriever: AssetRetriever
    let httpServer: GCDHTTPServer
    let book: CalibreBook?
}

protocol YabrReadiumMetaSource {
    func yabrReadiumReadPosition(_ viewController: YabrReadiumReaderViewController) -> BookDeviceReadingPosition?
    func yabrReadiumReadPosition(_ viewController: YabrReadiumReaderViewController, update readPosition: (Double, Double, [String: Any], String))
    func yabrReadiumDictViewer(_ viewController: YabrReadiumReaderViewController) -> (String, UINavigationController)?
}

/// This class is meant to be subclassed by each publication format view controller. It contains the shared behavior, eg. navigation bar toggling.
class YabrReadiumReaderViewController:
    UIViewController, Loggable, NavigatorDelegate, VisualNavigatorDelegate {
    
    let navigator: UIViewController & Navigator
    let publication: Publication
    let initialLocation: Locator?
    
    let environment: YabrReadiumEnvironment
    
    var readiumMetaSource: YabrReadiumMetaSource? = nil
    
    private(set) var stackView: UIStackView!
    private var stackViewTopConstraint: NSLayoutConstraint!
    
    private lazy var positionLabel = UILabel()
    
    /// This regex matches any string with at least 2 consecutive letters (not limited to ASCII).
    /// It's used when evaluating whether to display the body of a noteref referrer as the note's title.
    /// I.e. a `*` or `1` would not be used as a title, but `on` or `好書` would.
    private static var noterefTitleRegex: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "[\\p{Ll}\\p{Lu}\\p{Lt}\\p{Lo}]{2}")
    }()
    
    init(navigator: UIViewController & Navigator, publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        self.initialLocation = initialLocation
        self.navigator = navigator
        self.publication = publication
        self.environment = environment

        super.init(nibName: nil, bundle: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(voiceOverStatusDidChange), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Allow content to flow behind navigation bar
        self.edgesForExtendedLayout = .all
        self.extendedLayoutIncludesOpaqueBars = true
        
        view.backgroundColor = .white
      
        navigationItem.rightBarButtonItems = makeNavigationBarButtons()
        updateNavigationBar(animated: false)
        
        stackView = UIStackView(frame: view.bounds)
        stackView.distribution = .fill
        stackView.axis = .vertical
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Pin stackView to view.topAnchor with a dynamic constraint to handle status bar vs nav bar
        stackViewTopConstraint = stackView.topAnchor.constraint(equalTo: view.topAnchor)
        
        NSLayoutConstraint.activate([
            stackViewTopConstraint,
            stackView.rightAnchor.constraint(equalTo: view.rightAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.leftAnchor.constraint(equalTo: view.leftAnchor)
        ])

        addChild(navigator)
        stackView.addArrangedSubview(navigator.view)
        navigator.didMove(toParent: self)
        
        stackView.addArrangedSubview(accessibilityToolbar)
        
        positionLabel.translatesAutoresizingMaskIntoConstraints = false
        positionLabel.font = .systemFont(ofSize: 12)
        positionLabel.textColor = .darkGray
        view.addSubview(positionLabel)
        NSLayoutConstraint.activate([
            positionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            positionLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Calculate the effective top inset to avoid status bar but ignore navigation bar
        let statusBarHeight = view.window?.safeAreaInsets.top ?? 0
        
        // Update constraint to ensure content starts exactly below the system safe area inset (status bar)
        // while allowing it to be covered by the navigation bar when it appears.
        if stackViewTopConstraint.constant != statusBarHeight {
            stackViewTopConstraint.constant = statusBarHeight
        }
    }
    
    override func willMove(toParent parent: UIViewController?) {
        // Restore library's default UI colors
        navigationController?.navigationBar.tintColor = .black
        navigationController?.navigationBar.barTintColor = .white
    }
    
    
    // MARK: - Navigation bar
    
    private var navigationBarHidden: Bool = true {
        didSet {
            updateNavigationBar()
        }
    }
    
    func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons: [UIBarButtonItem] = []
        // Table of Contents
        buttons.append(UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"), style: .plain, target: self, action: #selector(presentOutline)))
        
        return buttons
    }
    
    func toggleNavigationBar() {
        navigationBarHidden = !navigationBarHidden
    }
    
    func updateNavigationBar(animated: Bool = true) {
        let hidden = navigationBarHidden && !UIAccessibility.isVoiceOverRunning
        navigationController?.setNavigationBarHidden(hidden, animated: animated)
        setNeedsStatusBarAppearanceUpdate()
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .slide
    }
    
    override var prefersStatusBarHidden: Bool {
        return false
    }

    
    // MARK: - Outlines

    @objc func presentOutline() {
        // Display YABR TOC UI here
    }
    
    // MARK: - Accessibility
    
    /// Constraint used to shift the content under the navigation bar, since it is always visible when VoiceOver is running.
    private lazy var accessibilityTopMargin: NSLayoutConstraint = {
        return self.stackView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor)
    }()
    
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
    
    @objc private func voiceOverStatusDidChange() {
        let isRunning = UIAccessibility.isVoiceOverRunning
        // Avoids excessive settings refresh when the status didn't change.
        guard isVoiceOverRunning != isRunning else {
            return
        }
        isVoiceOverRunning = isRunning
        accessibilityTopMargin.isActive = isRunning
        accessibilityToolbar.isHidden = !isRunning
        updateNavigationBar()
    }
    
    @objc private func goBackward() {
        Task { await navigator.goBackward() }
    }
    
    @objc private func goForward() {
        Task { await navigator.goForward() }
    }
    
    
    // MARK: - NavigatorDelegate
    func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
        log(.error, "ReadiumReaderViewController didFailToLoadResourceAt \(href.string) \(error)")
    }

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {

        positionLabel.text = {
            if let position = locator.locations.position {
                return "\(position) / \(self.publication.readingOrder.count)"
            } else {
                return ""
            }
        }()
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        log(.error, "ReadiumReaderViewController presentError \(error)")
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        let viewport = view.bounds
        let leftEdge = viewport.width * 0.2
        let rightEdge = viewport.width * 0.8
        
        let isScroll = (navigator as? EPUBNavigatorViewController)?.settings.scroll ?? false
        
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
}
