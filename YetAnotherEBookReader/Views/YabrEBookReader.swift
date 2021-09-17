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
#if canImport(R2Shared)
import R2Shared
import R2Streamer
#endif

@available(macCatalyst 14.0, *)
struct YabrEBookReader: UIViewControllerRepresentable {
    
    let bookURL : URL
    let bookFormat: Format
    let bookReader: ReaderType
    let bookPosition: BookDeviceReadingPosition
    
    @EnvironmentObject var modelData: ModelData
    
    init(readerInfo: ReaderInfo) {
        bookURL = readerInfo.url
        bookFormat = readerInfo.format
        bookReader = readerInfo.readerType
        bookPosition = readerInfo.position
    }
    
    init(url: URL, format: Format, reader: ReaderType, position: BookDeviceReadingPosition) {
        self.bookURL = url
        self.bookFormat = format
        self.bookReader = reader
        self.bookPosition = position
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let nav = UINavigationController()
        #if canImport(R2Shared)
        if bookFormat == Format.EPUB && bookReader == ReaderType.ReadiumEPUB {
            
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
                    
                    if bookPosition.lastReadPage > 0,
                       bookPosition.lastReadPage - 1 < publication.readingOrder.count {
                        let link = publication.readingOrder[bookPosition.lastReadPage - 1]
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: bookPosition.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: bookPosition.lastChapterProgress / 100.0,
                                totalProgression: bookPosition.lastProgress / 100.0,
                                position: bookPosition.lastPosition[1],
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
        #endif
        
        if bookFormat == Format.EPUB && bookReader == ReaderType.FolioReader {
            let readerConfiguration = FolioReaderConfiguration(bookURL: bookURL)
            readerConfiguration.enableTTS = false
            readerConfiguration.allowSharing = false
//            readerConfiguration.hideBars = true
//            readerConfiguration.hidePageIndicator = true
//            readerConfiguration.shouldHideNavigationOnTap = true
            guard let unzipPath = makeFolioReaderUnzipPath() else {
                return nav
            }
            let folioReader = FolioReader()
            let epubReaderContainer = EpubFolioReaderContainer(withConfig: readerConfiguration, folioReader: folioReader, epubPath: bookURL.path, unzipPath: unzipPath.path, removeEpub: false)
            
            epubReaderContainer.modelData = modelData
            epubReaderContainer.open(bookReadingPosition: bookPosition)
            return epubReaderContainer
        }
        
        #if canImport(R2Shared)
        if bookFormat == Format.PDF && bookReader == ReaderType.ReadiumPDF {
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
                    
                    if bookPosition.lastReadPage > 0,
                       bookPosition.lastReadPage - 1 < publication.metadata.numberOfPages ?? 0,
                       let link = publication.readingOrder.first {
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: bookPosition.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: bookPosition.lastChapterProgress / 100.0,
                                totalProgression: bookPosition.lastProgress / 100.0,
                                position: bookPosition.lastPosition[0],
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
        #endif
        
        if bookFormat == Format.PDF && bookReader == ReaderType.YabrPDFView {
            let pdfViewController = YabrPDFViewController()
            
            let nav = UINavigationController(rootViewController: pdfViewController)
            nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
            nav.navigationBar.isTranslucent = false
            nav.setToolbarHidden(false, animated: true)
            
            pdfViewController.open(pdfURL: bookURL, position: bookPosition)
            pdfViewController.modelData = modelData
            
            
            return nav
        }
        
        #if canImport(R2Shared)
        if bookFormat == Format.CBZ && bookReader == ReaderType.ReadiumCBZ {
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
                    
                    if bookPosition.lastReadPage > 0,
                       bookPosition.lastReadPage - 1 < publication.readingOrder.count {
                        let link = publication.readingOrder[bookPosition.lastReadPage - 1]
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: bookPosition.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: bookPosition.lastChapterProgress / 100.0,
                                totalProgression: bookPosition.lastProgress / 100.0,
                                position: bookPosition.lastPosition[1],
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
        #endif
        
        return UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // vc.bookDetailView = bookDetailView
        // uiViewController.open(epubURL: bookURL)
        // print("EBookReader updateUIViewController \(context)")
    }
    
}

func FolioReaderConfiguration(bookURL: URL) -> FolioReaderConfig {
    let config = FolioReaderConfig(withIdentifier: bookURL.lastPathComponent)
    config.shouldHideNavigationOnTap = false
    config.scrollDirection = FolioReaderScrollDirection.vertical
    config.allowSharing = true
    config.displayTitle = true
    
    #if DEBUG
//    config.debug.formUnion([.borderHighlight])
    config.debug.formUnion([.viewTransition])
    config.debug.formUnion([.functionTrace])
    //config.debug.formUnion([.htmlStyling, .borderHighlight])
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
