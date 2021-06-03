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
import R2Shared
import R2Streamer

@available(macCatalyst 14.0, *)
struct EBookReaderSwiftUI: UIViewControllerRepresentable {
    
    let bookURL : URL
    let bookFormat: CalibreBook.Format
    let bookReader: ReaderType
    
    @EnvironmentObject var modelData: ModelData
    
    func makeUIViewController(context: Context) -> UIViewController {
        let nav = UINavigationController()
        if bookFormat == CalibreBook.Format.EPUB && bookReader == ReaderType.ReadiumReader {
            
            guard let server = PublicationServer() else {
                return nav
            }
            
            let streamer = Streamer()
            
            let asset = FileAsset(url: bookURL)
            
            streamer.open(asset: asset, allowUserInteraction: true) { result in
                do {
                    let publication = try result.get()
                    server.removeAll()
                    try server.add(publication)
                    let book = Book(href: bookURL.lastPathComponent, title: publication.metadata.title, author: publication.metadata.authors.map{$0.name}.joined(separator: ", "), identifier: publication.metadata.identifier ?? bookURL.lastPathComponent, cover: publication.cover?.pngData())
                    
                    if let bookReadingPosition = modelData.getSelectedReadingPosition(),
                       bookReadingPosition.lastReadPage > 0,
                       bookReadingPosition.lastReadPage - 1 < publication.readingOrder.count {
                        let link = publication.readingOrder[bookReadingPosition.lastReadPage - 1]
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: bookReadingPosition.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: bookReadingPosition.lastChapterProgress / 100.0,
                                totalProgression: bookReadingPosition.lastProgress / 100.0,
                                position: bookReadingPosition.lastPosition[1],
                                otherLocations: [:]),
                            text: Locator.Text())
                        book.progression = locator.jsonString
                    }
                    
                    let readerVC = EpubReadiumReaderContainer(publication: publication, book: book, resourcesServer: server)
                    readerVC.modelData = modelData
                    readerVC.open()
                    nav.pushViewController(readerVC, animated: false)
                } catch {
                    print(error)
                }
            }
            
            return nav
        }
        
        if bookFormat == CalibreBook.Format.EPUB && bookReader == ReaderType.FolioReader {
            let readerConfiguration = self.readerConfiguration()
            readerConfiguration.enableTTS = false
            readerConfiguration.allowSharing = false
            guard let unzipPath = makeFolioReaderUnzipPath() else {
                return nav
            }
            let folioReader = FolioReader()
            let epubReaderContainer = EpubFolioReaderContainer(withConfig: readerConfiguration, folioReader: folioReader, epubPath: bookURL.path, unzipPath: unzipPath.path, removeEpub: false)
            
            epubReaderContainer.modelData = modelData
            epubReaderContainer.open()
            return epubReaderContainer
        }
        
        if bookFormat == CalibreBook.Format.PDF && bookReader == ReaderType.ReadiumReader {
            let nav = UINavigationController()
            
            guard let server = PublicationServer() else {
                return nav
            }
            let streamer = Streamer()
            
            let asset = FileAsset(url: bookURL)
            
            streamer.open(asset: asset, allowUserInteraction: true) { result in
                do {
                    let publication = try result.get()
                    server.removeAll()
                    try server.add(publication)
                    
                    let book = Book(href: bookURL.lastPathComponent, title: publication.metadata.title, author: publication.metadata.authors.map{$0.name}.joined(separator: ", "), identifier: publication.metadata.identifier ?? bookURL.lastPathComponent, cover: publication.cover?.pngData())
                    
                    if let bookReadingPosition = modelData.getSelectedReadingPosition(),
                       bookReadingPosition.lastReadPage > 0,
                       bookReadingPosition.lastReadPage - 1 < publication.metadata.numberOfPages ?? 0,
                       let link = publication.readingOrder.first {
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: bookReadingPosition.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: bookReadingPosition.lastChapterProgress / 100.0,
                                totalProgression: bookReadingPosition.lastProgress / 100.0,
                                position: bookReadingPosition.lastPosition[0],
                                otherLocations: [:]),
                            text: Locator.Text())
                        book.progression = locator.jsonString
                    }
                    
                    let readerVC = PDFViewController(publication: publication, book: book)
                    let closeItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction(handler: { _ in
                        readerVC.dismiss(animated: true, completion: nil)
                    }))
                    
                    readerVC.navigationItem.leftBarButtonItem = closeItem
                    
                    
                    nav.pushViewController(readerVC, animated: false)
                } catch {
                    print(error)
                }
            }
            
            return nav
        }
        
        if bookFormat == CalibreBook.Format.PDF && bookReader == ReaderType.YabrPDFView {
            let pdfViewController = YabrPDFViewController()
            
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
        
        if bookFormat == CalibreBook.Format.CBZ && bookReader == ReaderType.ReadiumReader {
            let nav = UINavigationController()
            
            guard let server = PublicationServer() else {
                return nav
            }
            
            let streamer = Streamer()
            
            let asset = FileAsset(url: bookURL)
            
            streamer.open(asset: asset, allowUserInteraction: true) { result in
                do {
                    let publication = try result.get()
                    server.removeAll()
                    try server.add(publication)
                    let book = Book(href: bookURL.lastPathComponent, title: publication.metadata.title, author: publication.metadata.authors.map{$0.name}.joined(separator: ", "), identifier: publication.metadata.identifier ?? bookURL.lastPathComponent, cover: publication.cover?.pngData())
                    
                    if let bookReadingPosition = modelData.getSelectedReadingPosition(),
                       bookReadingPosition.lastReadPage > 0,
                       bookReadingPosition.lastReadPage - 1 < publication.readingOrder.count {
                        let link = publication.readingOrder[bookReadingPosition.lastReadPage - 1]
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: bookReadingPosition.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: bookReadingPosition.lastChapterProgress / 100.0,
                                totalProgression: bookReadingPosition.lastProgress / 100.0,
                                position: bookReadingPosition.lastPosition[1],
                                otherLocations: [:]),
                            text: Locator.Text())
                        book.progression = locator.jsonString
                    }
                    
                    let readerVC = CBZViewController(publication: publication, book: book)
                    let closeItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction(handler: { _ in
                        readerVC.dismiss(animated: true, completion: nil)
                    }))
                    
                    readerVC.navigationItem.leftBarButtonItem = closeItem
                    nav.pushViewController(readerVC, animated: false)
                } catch {
                    print(error)
                }
            }
            
            return nav
        }
        
        return UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // vc.bookDetailView = bookDetailView
        // uiViewController.open(epubURL: bookURL)
        print("EBookReader updateUIViewController \(context)")
    }
    
    private func readerConfiguration() -> FolioReaderConfig {
        let config = FolioReaderConfig(withIdentifier: bookURL.lastPathComponent)
        config.shouldHideNavigationOnTap = false
        config.scrollDirection = FolioReaderScrollDirection.vertical
        config.allowSharing = true
        
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