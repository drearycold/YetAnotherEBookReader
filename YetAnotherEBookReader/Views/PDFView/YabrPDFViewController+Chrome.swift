//
//  YabrPDFViewController+Chrome.swift
//  YetAnotherEBookReader
//

import PDFKit
import SwiftUI
import UIKit

@available(macCatalyst 14.0, *)
extension YabrPDFViewController {
    private enum ChromeMetrics {
        static let horizontalMargin: CGFloat = 16.0
        static let horizontalPadding: CGFloat = 8.0
        static let verticalPadding: CGFloat = 5.0
        static let height: CGFloat = 34.0
    }

    func configureReaderChrome() {
        let backgroundColor = UIColor(cgColor: pdfOptions.fillColor)
        self.navigationController?.navigationBar.barTintColor = backgroundColor
        self.navigationController?.navigationBar.backgroundColor = backgroundColor
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
        pdfView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(pdfView)

        let bottomConstraint = pdfView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        self.pdfViewBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: self.view.topAnchor),
            bottomConstraint,
            pdfView.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            pdfView.rightAnchor.constraint(equalTo: self.view.rightAnchor)
        ])
    }

    func configureSelectionOverlay() {
        let defaultMenuItems = buildDefaultMenuItems()
        UIMenuController.shared.menuItems = defaultMenuItems
        UIMenuController.shared.update()

        UIMenuController.installTo(responder: self.pdfView)

        guard #available(iOS 16.0, *) else { return }

        self.annotationView.isHidden = true
        self.view.addSubview(self.annotationView)

        self.annotationView.underlineButton.addTarget(nil, action: #selector(highlightAction(_:)), for: .primaryActionTriggered)
        self.annotationView.highlightButton.addTarget(nil, action: #selector(highlightAction(_:)), for: .primaryActionTriggered)
        self.annotationView.dictViewerButton.addTarget(nil, action: #selector(dictViewerAction(_:)), for: .primaryActionTriggered)

        NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: pdfView, queue: nil) { [self] _ in
            guard let selection = pdfView.currentSelection,
                  let selectionString = selection.string,
                  selectionString.count > 0
            else {
                annotationView.isHidden = true
                return
            }

            guard let selectionLastLine = selection.selectionsByLine().last,
                  let selectionLastLinePage = selectionLastLine.pages.last
            else {
                annotationView.isHidden = true
                return
            }

            let selectionBound = selectionLastLine.bounds(for: selectionLastLinePage)
            let selectionInView = pdfView.convert(selectionBound, from: selectionLastLinePage)

            let buttonSize = CGFloat(48)
            let padding = CGFloat(32)

            let annotationViewSize = CGSize(width: buttonSize, height: CGFloat(annotationView.arrangedSubviews.count) * buttonSize)

            var annotationViewPosition = CGPoint(
                x: selectionInView.maxX + padding / 2.0,
                y: selectionInView.maxY + padding / 2.0
            )

            if annotationViewPosition.x + annotationViewSize.width + padding > pdfView.frame.width {
                annotationViewPosition.x = pdfView.frame.width - buttonSize - padding
            }

            if annotationViewPosition.y + annotationViewSize.height + padding > pdfView.frame.height {
                annotationViewPosition.y = selectionInView.minY - CGFloat(annotationView.arrangedSubviews.count) * buttonSize - padding * 2.0
            }

            annotationView.frame = .init(origin: annotationViewPosition, size: annotationViewSize)

            annotationView.backgroundColor = pdfOptions.isDark(
                UIColor.black.withAlphaComponent(0.9),
                UIColor.white.withAlphaComponent(0.9)
            )

            annotationView.isHidden = false
        }
    }

    func configureThumbnailPreview() {
        self.thumbImageView.translatesAutoresizingMaskIntoConstraints = false
        self.thumbController.view.addSubview(self.thumbImageView)
        NSLayoutConstraint.activate([
            self.thumbImageView.topAnchor.constraint(equalTo: self.thumbController.view.topAnchor),
            self.thumbImageView.bottomAnchor.constraint(equalTo: self.thumbController.view.bottomAnchor),
            self.thumbImageView.leadingAnchor.constraint(equalTo: self.thumbController.view.leadingAnchor),
            self.thumbImageView.trailingAnchor.constraint(equalTo: self.thumbController.view.trailingAnchor)
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
        pageIndicator.addAction(UIAction(handler: { [self] _ in
            guard let curPageNum = pdfView.currentPage?.pageRef?.pageNumber,
                  let bounds = marginCropController.cachedValue(for:
                    PageVisibleContentKey(
                        pageNumber: curPageNum,
                        readingDirection: pdfOptions.readingDirection,
                        hMarginDetectStrength: pdfOptions.hMarginDetectStrength,
                        vMarginDetectStrength: pdfOptions.vMarginDetectStrength
                    )
                  ),
                  let image = bounds.thumbImage else { return }
            self.thumbImageView.image = image

            let pageController = YabrPDFNavigationPageVC()
            pageController.pdfViewController = self
            pageController.yabrPDFView = self.pdfView
            pageController.yabrPDFMetaSource = self.yabrPDFMetaSource

            let nav = UINavigationController(rootViewController: pageController)
            if let fillColor = PDFPageWithBackground.fillColor {
                nav.navigationBar.backgroundColor = UIColor(cgColor: fillColor)
                nav.navigationBar.barTintColor = UIColor(cgColor: fillColor)
            }

            self.present(nav, animated: true)

        }), for: .primaryActionTriggered)

        pageSlider.minimumValue = 1
        pageSlider.maximumValue = Float(pdfView.document?.pageCount ?? 1)
        pageSlider.isContinuous = true
        pageSlider.addAction(UIAction(handler: { _ in
            guard let currentPageNumber = self.pdfView.currentPage?.pageRef?.pageNumber else { return }
            let destPageNumber = Int(self.pageSlider.value.rounded())
            print("\(#function) current=\(currentPageNumber) target=\(destPageNumber)")

            guard currentPageNumber != destPageNumber,
                  let destPage = self.pdfView.document?.page(at: destPageNumber - 1) else { return }

            self.addBlankSubView(page: destPage)
            self.pdfView.go(to: destPage)
        }), for: .valueChanged)

        pagePrevButton.setImage(UIImage(systemName: "arrow.left"), for: .normal)
        pagePrevButton.addAction(UIAction(handler: { _ in
            self.updatePageViewPositionHistory()
            self.addBlankSubView(page: self.pdfView.currentPage)

            if self.pdfView.displaysRTL {
                self.pdfView.goToNextPage(self.pagePrevButton)
            } else {
                self.pdfView.goToPreviousPage(self.pagePrevButton)
            }
        }), for: .primaryActionTriggered)

        pageNextButton.setImage(UIImage(systemName: "arrow.right"), for: .normal)
        pageNextButton.addAction(UIAction(handler: { _ in
            self.updatePageViewPositionHistory()
            self.addBlankSubView(page: self.pdfView.currentPage)

            if self.pdfView.displaysRTL {
                self.pdfView.goToPreviousPage(self.pagePrevButton)
            } else {
                self.pdfView.goToNextPage(self.pagePrevButton)
            }
        }), for: .primaryActionTriggered)

        pageBackButton.setImage(UIImage(systemName: "arrow.uturn.left"), for: .normal)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.axis = .horizontal
        stackView.spacing = 16.0

        if #available(iOS 16.0, *) {
            pageBackButton.isHidden = true
            stackView.addArrangedSubview(pageBackButton)

            let pageBackAction = UIAction(handler: { _ in
                guard let historyItem = self.historyMenu.children.last as? UIAction
                else {
                    return
                }
                self.addBlankSubView(page: self.pdfView.currentPage)
                historyItem.performWithSender(self, target: self.pdfView)
            })

            pageBackButton.addAction(pageBackAction, for: .primaryActionTriggered)
        }

        pageAuxButton.setImage(UIImage(systemName: "square.split.bottomrightquarter"), for: .normal)
        pageAuxButton.addAction(.init(handler: { [self] _ in
            if pdfViewAux.superview == nil {
                pdfViewAux.backgroundColor = pdfView.backgroundColor

                pdfViewAux.frame = .init(
                    origin: .init(x: 150.0, y: view.frame.height - 260),
                    size: .init(width: pdfView.frame.width - 200.0, height: 200.0)
                )

                if pdfViewAux.document == nil {
                    pdfViewAux.document = pdfView.document

                    pdfViewAux.layer.borderWidth = 2
                    pdfViewAux.layer.cornerRadius = 8
                    pdfViewAux.layer.shadowRadius = 16

                    pdfViewAux.scaleFactor = pdfView.scaleFactor * 0.8
                    pdfViewAux.displayMode = .singlePageContinuous
                    pdfViewAux.displayDirection = .vertical
                    pdfViewAux.interpolationQuality = .high

                    if let currentDestination = pdfView.currentDestination {
                        pdfViewAux.go(to: currentDestination)
                    }
                }

                view.addSubview(pdfViewAux)
            } else {
                pdfViewAux.removeFromSuperview()
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
            UIBarButtonItem(image: UIImage(systemName: "xmark.circle"), style: .done, target: self, action: #selector(finishReading(sender:))),
            UIBarButtonItem(title: "Navigations", image: UIImage(systemName: "list.bullet"), primaryAction: UIAction(handler: { _ in
                let navigationController = YabrPDFNavigationPageVC()
                navigationController.pdfViewController = self
                navigationController.yabrPDFView = self.pdfView
                navigationController.yabrPDFMetaSource = self.yabrPDFMetaSource

                let nav = UINavigationController(rootViewController: navigationController)
                if let fillColor = PDFPageWithBackground.fillColor {
                    nav.navigationBar.backgroundColor = UIColor(cgColor: fillColor)
                    nav.navigationBar.barTintColor = UIColor(cgColor: fillColor)
                }

                self.present(nav, animated: true)
            })),
            UIBarButtonItem(title: "Annotations", image: UIImage(systemName: "bookmark"), primaryAction: UIAction(handler: { _ in
                let annotationController = YabrPDFAnnotationPageVC()
                annotationController.pdfViewController = self
                annotationController.yabrPDFView = self.pdfView
                annotationController.yabrPDFMetaSource = self.yabrPDFMetaSource

                let nav = UINavigationController(rootViewController: annotationController)
                if let fillColor = PDFPageWithBackground.fillColor {
                    nav.navigationBar.backgroundColor = UIColor(cgColor: fillColor)
                    nav.navigationBar.barTintColor = UIColor(cgColor: fillColor)
                }

                self.present(nav, animated: true)
            }))
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
                primaryAction: UIAction { _ in
                    let optionViewModel = PDFOptionViewModel(preferences: self.pdfOptions) { [weak self] updatedPreferences in
                        guard let self else { return }
                        self.updatePageViewPositionHistory()
                        self.handleOptionsChange(pdfOptions: updatedPreferences)
                    }
                    let optionView = PDFOptionView(model: optionViewModel)

                    let optionViewController = UIHostingController(rootView: optionView.fixedSize())
                    optionViewController.preferredContentSize = CGSize(width: 340, height: 700)
                    optionViewController.modalPresentationStyle = .popover
                    optionViewController.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItems?[1]

                    self.present(optionViewController, animated: true, completion: nil)
                }
            ),
            shareBarButtonItem
        ], animated: true)
        self.navigationItem.rightBarButtonItems?.first?.isEnabled = false
    }
}
