//
//  ReaderView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/26.
//

import Foundation
import UIKit
import SwiftUI
import FolioReaderKit

@available(macCatalyst 14.0, *)
struct EpubReader: UIViewControllerRepresentable {
    
    let bookURL : URL
    @EnvironmentObject var modelData: ModelData
    
    func makeUIViewController(context: Context) -> UIViewController {
        if bookURL.path.hasSuffix(".epub") {
            let readerConfiguration = self.readerConfiguration()
            readerConfiguration.enableTTS = false
            readerConfiguration.allowSharing = false
            let folioReader = FolioReader()
            let epubReaderContainer = EpubReaderContainer(withConfig: readerConfiguration, folioReader: folioReader, epubPath: bookURL.path)
            epubReaderContainer.modelData = modelData
            epubReaderContainer.open()
            return epubReaderContainer
        }
        
        if bookURL.path.hasSuffix(".pdf") {
            let pdfViewController = PDFViewController()
            
            let nav = UINavigationController(rootViewController: pdfViewController)
            nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
            nav.navigationBar.isTranslucent = false
            nav.setToolbarHidden(false, animated: true)
            
            pdfViewController.open(pdfURL: bookURL)
            pdfViewController.modelData = modelData
            
            let stackView = UIStackView(frame: nav.toolbar.frame)
            stackView.distribution = .fill
            stackView.alignment = .fill
            stackView.axis = .horizontal
            stackView.spacing = 16.0
            
            stackView.addArrangedSubview(pdfViewController.pagePrevButton)
            stackView.addArrangedSubview(pdfViewController.pageSlider)
            stackView.addArrangedSubview(pdfViewController.pageIndicator)
            stackView.addArrangedSubview(pdfViewController.pageNextButton)
            
            let toolbarView = UIBarButtonItem(customView: stackView)
            pdfViewController.setToolbarItems([toolbarView], animated: false)
            
            return nav
        }
        
        return UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // vc.bookDetailView = bookDetailView
        // uiViewController.open(epubURL: bookURL)
        
    }
    
    private func readerConfiguration() -> FolioReaderConfig {
        let config = FolioReaderConfig(withIdentifier: bookURL.lastPathComponent)
        config.shouldHideNavigationOnTap = false
        config.scrollDirection = FolioReaderScrollDirection.vertical
        #if DEBUG
        config.debug = 1
        #endif
        // See more at FolioReaderConfig.swift
//        config.canChangeScrollDirection = false
//        config.enableTTS = false
//        config.displayTitle = true
//        config.allowSharing = false
//        config.tintColor = UIColor.blueColor()
//        config.toolBarTintColor = UIColor.redColor()
//        config.toolBarBackgroundColor = UIColor.purpleColor()
//        config.menuTextColor = UIColor.brownColor()
//        config.menuBackgroundColor = UIColor.lightGrayColor()
//        config.hidePageIndicator = true
//        config.realmConfiguration = Realm.Configuration(fileURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("highlights.realm"))

        // Custom sharing quote background
        config.quoteCustomBackgrounds = []
        if let image = UIImage(named: "demo-bg") {
            let customImageQuote = QuoteImage(withImage: image, alpha: 0.6, backgroundColor: UIColor.black)
            config.quoteCustomBackgrounds.append(customImageQuote)
        }

        let textColor = UIColor(red:0.86, green:0.73, blue:0.70, alpha:1.0)
        let customColor = UIColor(red:0.30, green:0.26, blue:0.20, alpha:1.0)
        let customQuote = QuoteImage(withColor: customColor, alpha: 1.0, textColor: textColor)
        config.quoteCustomBackgrounds.append(customQuote)

        return config
    }

    
}
