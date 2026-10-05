//
//  YabrPDFViewController+Chrome.swift
//  YetAnotherEBookReader
//

import PDFKit
import SwiftUI
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
extension YabrPDFViewController {
    private enum ChromeMetrics {
        static let horizontalMargin: CGFloat = 16.0
        static let horizontalPadding: CGFloat = 8.0
        static let verticalPadding: CGFloat = 5.0
        static let height: CGFloat = 34.0
    }

    func configureReaderChrome() {
        let backgroundColor = UIColor(cgColor: pdfOptions.fillColor)
        self.navigationController?.toolbar.barTintColor = backgroundColor
        self.navigationController?.toolbar.backgroundColor = backgroundColor
        self.tabBarController?.tabBar.barTintColor = backgroundColor
        self.tabBarController?.tabBar.backgroundColor = backgroundColor

        configurePagingControls()
        configureNavigationItems()
        applyChromeTheme()

        buildTocList()

        let docTitle = self.pdfView.document?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        titleInfoButton.setTitle(docTitle ?? "", for: .normal)
        titleInfoButton.contentHorizontalAlignment = .center
        titleInfoButton.showsMenuAsPrimaryAction = true
        titleInfoButton.frame = CGRect(x: 0, y: 0, width: navigationController?.navigationBar.frame.width ?? 600 / 2, height: 40)

        navigationItem.titleView = titleInfoButton

        pdfView.delegate = self
        surface.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(surface)

        let bottomConstraint = surface.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        self.pdfViewBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: self.view.topAnchor),
            bottomConstraint,
            surface.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            surface.rightAnchor.constraint(equalTo: self.view.rightAnchor)
        ])
    }

    private func configurePagingControls() {
        chromeContainerView.translatesAutoresizingMaskIntoConstraints = false
        chromeContainerView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(view.bounds.width - ChromeMetrics.horizontalMargin, 0),
            height: ChromeMetrics.height
        )
        chromeContainerView.clipsToBounds = false
        chromeContainerView.layer.masksToBounds = false

        pageIndicator.setTitle("0 / 0", for: .normal)
        pageIndicator.addAction(UIAction { [weak self] _ in
            self?.presentNavigation()
        }, for: .primaryActionTriggered)

        pageSlider.minimumValue = 1
        pageSlider.maximumValue = Float(pdfView.document?.pageCount ?? 1)
        pageSlider.isContinuous = true
        pageSlider.addAction(UIAction(handler: { _ in
            guard let currentPageNumber = self.pdfView.currentPage?.pageRef?.pageNumber else { return }
            let destPageNumber = Int(self.pageSlider.value.rounded())
            print("\(#function) current=\(currentPageNumber) target=\(destPageNumber)")

            guard currentPageNumber != destPageNumber,
                  let destPage = self.pdfView.document?.page(at: destPageNumber - 1) else { return }

            self.markJumpTarget(destPage)
            self.pdfView.go(to: destPage)
        }), for: .valueChanged)

        pagePrevButton.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        pagePrevButton.addAction(UIAction(handler: { _ in
            self.turnPage(forward: self.pdfView.displaysRTL)
        }), for: .primaryActionTriggered)

        pageNextButton.setImage(UIImage(systemName: "arrow.right"), for: .normal)
        pageNextButton.addAction(UIAction(handler: { _ in
            self.turnPage(forward: !self.pdfView.displaysRTL)
        }), for: .primaryActionTriggered)

        pageBackButton.setImage(UIImage(systemName: "arrow.uturn.left"), for: .normal)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.axis = .horizontal
        stackView.spacing = 16.0

        pageBackButton.isHidden = true
        stackView.addArrangedSubview(pageBackButton)

        let pageBackAction = UIAction(handler: { _ in
            guard let historyItem = self.historyMenu.children.last as? UIAction
            else {
                return
            }
            historyItem.performWithSender(self, target: self.pdfView)
        })

        pageBackButton.addAction(pageBackAction, for: .primaryActionTriggered)

        pageAuxButton.setImage(UIImage(systemName: "square.split.bottomrightquarter"), for: .normal)
        pageAuxButton.addAction(.init(handler: { [self] _ in
            if auxSurface.superview == nil {
                pdfViewAux.backgroundColor = pdfView.backgroundColor

                auxSurface.frame = .init(
                    origin: .init(x: 150.0, y: view.frame.height - 260),
                    size: .init(width: pdfView.frame.width - 200.0, height: 200.0)
                )
                // Size the page view before it is scaled.
                auxSurface.layoutIfNeeded()

                if pdfViewAux.document == nil {
                    pdfViewAux.document = pdfView.document

                    auxSurface.layer.borderWidth = 2
                    auxSurface.layer.cornerRadius = 8
                    auxSurface.layer.shadowRadius = 16

                    pdfViewAux.scaleFactor = pdfView.scaleFactor * 0.8
                    pdfViewAux.displayMode = .singlePageContinuous
                    pdfViewAux.displayDirection = .vertical
                    pdfViewAux.interpolationQuality = .high

                    if let currentDestination = pdfView.currentDestination {
                        pdfViewAux.go(to: currentDestination)
                    }
                }

                view.addSubview(auxSurface)
            } else {
                auxSurface.removeFromSuperview()
            }

        }), for: .primaryActionTriggered)

        stackView.addArrangedSubview(pagePrevButton)
        stackView.addArrangedSubview(pageSlider)
        stackView.addArrangedSubview(pageIndicator)
        stackView.addArrangedSubview(pageNextButton)
        stackView.addArrangedSubview(pageAuxButton)

        chromeContainerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: chromeContainerView.leadingAnchor, constant: ChromeMetrics.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: chromeContainerView.trailingAnchor, constant: -ChromeMetrics.horizontalPadding),
            stackView.topAnchor.constraint(equalTo: chromeContainerView.topAnchor, constant: ChromeMetrics.verticalPadding),
            stackView.bottomAnchor.constraint(equalTo: chromeContainerView.bottomAnchor, constant: -ChromeMetrics.verticalPadding)
        ])

        let widthConstraint = chromeContainerView.widthAnchor.constraint(equalToConstant: max(view.bounds.width - ChromeMetrics.horizontalMargin, 0))
        let heightConstraint = chromeContainerView.heightAnchor.constraint(equalToConstant: ChromeMetrics.height)
        NSLayoutConstraint.activate([widthConstraint, heightConstraint])
        chromeContainerWidthConstraint = widthConstraint
        chromeContainerHeightConstraint = heightConstraint

        let toolbarView = UIBarButtonItem(customView: chromeContainerView)
        setToolbarItems([toolbarView], animated: false)
    }

    func updateChromeContainerLayout() {
        chromeContainerWidthConstraint?.constant = max(view.bounds.width - ChromeMetrics.horizontalMargin, 0)
        chromeContainerHeightConstraint?.constant = ChromeMetrics.height
    }

    // MARK: Bars

    /// The insets the page is fitted to: the navigation controller's own safe
    /// area, which leaves out its bars. The bars float over the page and hide
    /// while reading, so showing or hiding them never moves it.
    var pageLayoutInsets: UIEdgeInsets {
        navigationController?.view.safeAreaInsets ?? view.safeAreaInsets
    }

    var readerBarsHidden: Bool {
        navigationController?.isNavigationBarHidden ?? false
    }

    /// Hides or shows the nav bar and toolbar. While they are hidden their share
    /// of the safe area moves into `additionalSafeAreaInsets`, so the page views'
    /// safe area, and with it PDFKit's scroll insets and the page placement,
    /// stays the same.
    func setReaderBarsHidden(_ hidden: Bool, animated: Bool) {
        cancelPendingBarReveal()
        guard let nav = navigationController, nav.isNavigationBarHidden != hidden else { return }
        if hidden {
            let insets = view.safeAreaInsets
            let base = pageLayoutInsets
            nav.setNavigationBarHidden(true, animated: animated)
            nav.setToolbarHidden(true, animated: animated)
            additionalSafeAreaInsets = UIEdgeInsets(
                top: max(0, insets.top - base.top),
                left: 0,
                bottom: max(0, insets.bottom - base.bottom),
                right: 0
            )
        } else {
            // A drag may have moved to another step while the bars were hidden.
            updatePageIndicator()
            additionalSafeAreaInsets = .zero
            nav.setNavigationBarHidden(false, animated: animated)
            nav.setToolbarHidden(false, animated: animated)
        }
    }

    /// A tap on the page, as in FolioReader: shown bars hide at once; hidden ones
    /// show after a moment, unless the tap turns out to start a selection
    /// (a double tap selects a word) or the page moves first.
    func requestBarToggle() {
        // Options keeps the bars hidden; its iPhone sheet leaves the page usable.
        guard !isPresentingOptions else {
            cancelPendingBarReveal()
            return
        }
        guard !readerBarsHidden else {
            cancelPendingBarReveal()
            let reveal = DispatchWorkItem { [weak self] in
                self?.pendingBarReveal = nil
                self?.setReaderBarsHidden(false, animated: true)
            }
            pendingBarReveal = reveal
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.barRevealDelay, execute: reveal)
            return
        }
        setReaderBarsHidden(true, animated: true)
    }

    /// PDF Options, with the bars hidden so the page they change shows in full:
    /// a popover at the top right, or on compact width a sheet that leaves the
    /// top half of the page visible. Closing it restores the bars.
    func presentOptions() {
        let optionViewModel = PDFOptionViewModel(preferences: pdfOptions) { [weak self] updatedPreferences in
            guard let self else { return }
            self.updatePageViewPositionHistory()
            self.handleOptionsChange(pdfOptions: updatedPreferences)
        }
        // Not `fixedSize()`: the sheet is shorter than the options, which scroll.
        let optionViewController = DismissAwareHostingController(rootView: PDFOptionView(model: optionViewModel))
        optionViewController.preferredContentSize = CGSize(width: 340, height: 700)
        optionViewController.modalPresentationStyle = .popover

        let barsWereHidden = readerBarsHidden
        isPresentingOptions = true
        setReaderBarsHidden(true, animated: true)
        optionViewController.onDismiss = { [weak self] in
            self?.isPresentingOptions = false
            self?.setReaderBarsHidden(barsWereHidden, animated: true)
        }

        if let popover = optionViewController.popoverPresentationController {
            // The Options button hides with the nav bar, so the popover is not
            // anchored to it.
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.maxX - 16, y: pageLayoutInsets.top + 8, width: 1, height: 1)
            popover.permittedArrowDirections = []

            let sheet = popover.adaptiveSheetPresentationController
            sheet.detents = [.medium(), .large()]
            sheet.largestUndimmedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }

        present(optionViewController, animated: true)
    }

    func cancelPendingBarReveal() {
        pendingBarReveal?.cancel()
        pendingBarReveal = nil
    }

    @objc func handleSelectionChangeForBars(_ notification: Notification) {
        guard notification.object as? YabrPDFView === pdfView, pdfView.currentSelection != nil else { return }
        cancelPendingBarReveal()
    }

    /// Sheets presented from the reader take the reader theme's nav bar.
    /// The search sheet; it keeps its query and results between presentations.
    func presentSearch() {
        let list = searchList
        list.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", primaryAction: UIAction { [weak list] _ in
            list?.dismiss(animated: true)
        })
        present(themedNavigationController(rootViewController: list), animated: true)
    }

    /// Sheets look like FolioReader's: the sheet surface, accent bar buttons.
    /// The contents and page thumbnails (`YabrPDFNavigationPageVC`), from the
    /// toolbar's list button and the page number.
    func presentNavigation() {
        let navigation = YabrPDFNavigationPageVC()
        navigation.pdfViewController = self
        navigation.yabrPDFMetaSource = yabrPDFMetaSource
        present(themedNavigationController(rootViewController: navigation), animated: true)
    }

    func themedNavigationController(rootViewController: UIViewController) -> UINavigationController {
        let palette = pdfOptions.themePalette
        palette.applySheet(to: rootViewController.navigationItem)
        let nav = UINavigationController(rootViewController: rootViewController)
        nav.overrideUserInterfaceStyle = palette.listStyle.userInterfaceStyle
        nav.navigationBar.tintColor = palette.listStyle.accent
        return nav
    }

    func applyChromeTheme() {
        let tintColor = pdfOptions.isDark(UIColor.lightText, UIColor.darkText)
        let secondaryTintColor = tintColor.withAlphaComponent(0.28)

        chromeContainerView.backgroundColor = .clear
        chromeContainerView.layer.cornerRadius = 0
        chromeContainerView.layer.masksToBounds = false
        chromeContainerView.clipsToBounds = false

        stackView.backgroundColor = .clear

        pageIndicator.setTitleColor(tintColor, for: .normal)
        titleInfoButton.setTitleColor(tintColor, for: .normal)

        pagePrevButton.tintColor = tintColor
        pageNextButton.tintColor = tintColor
        pageAuxButton.tintColor = tintColor
        pageBackButton.tintColor = tintColor
        pageBackButton.setTitleColor(tintColor, for: .normal)

        pageSlider.minimumTrackTintColor = tintColor
        pageSlider.maximumTrackTintColor = secondaryTintColor
        pageSlider.thumbTintColor = tintColor

        navigationController?.toolbar.tintColor = tintColor
    }

    private func configureNavigationItems() {
        navigationItem.setLeftBarButtonItems([
            UIBarButtonItem(title: "Navigations", image: UIImage(systemName: "list.bullet"), primaryAction: UIAction { [weak self] _ in
                self?.presentNavigation()
            }),
            UIBarButtonItem(title: "Annotations", image: UIImage(systemName: "bookmark"), primaryAction: UIAction(handler: { _ in
                let annotationController = YabrPDFAnnotationPageVC()
                annotationController.pdfViewController = self
                annotationController.yabrPDFMetaSource = self.yabrPDFMetaSource

                let nav = self.themedNavigationController(rootViewController: annotationController)

                self.present(nav, animated: true)
            })),
            // FolioReader's order: contents, bookmarks, search.
            UIBarButtonItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), primaryAction: UIAction { [weak self] _ in
                self?.presentSearch()
            })
        ], animated: true)

        let shareOriginalPDF = UIAction(title: "Original PDF") { [self] action in
            print("\(#function) \(action)")
            sharePDF(annotated: false)
        }

        let shareAnnotatedPDF = UIAction(title: "Annotated PDF") { [self] _ in
            sharePDF(annotated: true)
        }

        shareBarButtonItem.title = "Share"
        shareBarButtonItem.image = UIImage(systemName: "square.and.arrow.up")
        shareBarButtonItem.menu = UIMenu(children: [shareOriginalPDF, shareAnnotatedPDF])

        navigationItem.setRightBarButtonItems([
            UIBarButtonItem(image: UIImage(systemName: "clock"), menu: historyMenu),
            UIBarButtonItem(
                title: "Options",
                image: UIImage(systemName: "doc.badge.gearshape"),
                primaryAction: UIAction { [weak self] _ in
                    self?.presentOptions()
                }
            ),
            shareBarButtonItem
        ], animated: true)
        self.navigationItem.rightBarButtonItems?.first?.isEnabled = false
    }
}
