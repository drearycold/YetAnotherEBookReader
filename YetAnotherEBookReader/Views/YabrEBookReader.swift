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
    
    let moduleDelegate = YabrEBookReaderModuleDelegate()
    
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
                    
                    let readerVC = YabrReadiumEPUBViewController(publication: publication, book: book, resourcesServer: server)
                    
                    readerVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
                        systemItem: .close,
                        primaryAction: UIAction(
                            handler: { [self] _ in
                                readerVC.dismiss(animated: true, completion: nil)
                                
                                var updatedReadingPosition = modelData.updatedReadingPosition
                                
                                updatedReadingPosition.lastChapterProgress = readerVC.updatedReadingPosition.0 * 100
                                updatedReadingPosition.lastProgress = readerVC.updatedReadingPosition.1 * 100
                                
                                updatedReadingPosition.lastReadPage = readerVC.updatedReadingPosition.2["pageNumber"] as? Int ?? 1
                                updatedReadingPosition.lastPosition[0] = readerVC.updatedReadingPosition.2["pageNumber"] as? Int ?? 1
                                updatedReadingPosition.lastPosition[1] = readerVC.updatedReadingPosition.2["pageOffsetX"] as? Int ?? 0
                                updatedReadingPosition.lastPosition[2] = readerVC.updatedReadingPosition.2["pageOffsetY"] as? Int ?? 0
                                
                                
                                updatedReadingPosition.lastReadChapter = readerVC.updatedReadingPosition.3
                                updatedReadingPosition.readerName = ReaderType.ReadiumEPUB.rawValue
                                
                                modelData.updatedReadingPosition = updatedReadingPosition
                            }
                        )
                    )
                    readerVC.moduleDelegate = moduleDelegate

                    nav.pushViewController(readerVC, animated: false)
                } catch {
                    print(error)
                }
            }
            
            return nav
        }
        #endif
        
        if bookFormat == Format.EPUB && bookReader == ReaderType.YabrEPUB {
            let readerConfiguration = EpubFolioReaderContainer.Configuration(bookURL: bookURL)

            readerConfiguration.enableMDictViewer = modelData.getCustomDictViewer().0
            readerConfiguration.userFontDescriptors = modelData.userFontInfos.mapValues { $0.descriptor }
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
                    
                    let readerVC = YabrReadiumPDFViewController(publication: publication, book: book)
                    readerVC.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction(handler: { _ in
                        readerVC.dismiss(animated: true, completion: nil)
                        var updatedReadingPosition = modelData.updatedReadingPosition
                        
                        updatedReadingPosition.lastChapterProgress = readerVC.updatedReadingPosition.0 * 100
                        updatedReadingPosition.lastProgress = readerVC.updatedReadingPosition.1 * 100
                        
                        updatedReadingPosition.lastReadPage = readerVC.updatedReadingPosition.2["pageNumber"] as? Int ?? 1
                        updatedReadingPosition.lastPosition[0] = readerVC.updatedReadingPosition.2["pageNumber"] as? Int ?? 1
                        updatedReadingPosition.lastPosition[1] = readerVC.updatedReadingPosition.2["pageOffsetX"] as? Int ?? 0
                        updatedReadingPosition.lastPosition[2] = readerVC.updatedReadingPosition.2["pageOffsetY"] as? Int ?? 0
                        
                        updatedReadingPosition.lastReadChapter = readerVC.updatedReadingPosition.3
                        
                        updatedReadingPosition.readerName = ReaderType.ReadiumPDF.rawValue
                        
                        modelData.updatedReadingPosition = updatedReadingPosition
                    }))
                    
                    readerVC.moduleDelegate = moduleDelegate
                    
                    nav.pushViewController(readerVC, animated: false)
                } catch {
                    print(error)
                }
            }
            
            return nav
        }
        #endif
        
        if bookFormat == Format.PDF && bookReader == ReaderType.YabrPDF {
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
                    
                    let readerVC = YabrReadiumCBZViewController(publication: publication, book: book)
                    readerVC.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction(handler: { _ in
                        readerVC.dismiss(animated: true, completion: nil)
                        
                        var updatedReadingPosition = modelData.updatedReadingPosition
                        
                        updatedReadingPosition.lastChapterProgress = readerVC.updatedReadingPosition.0 * 100
                        updatedReadingPosition.lastProgress = readerVC.updatedReadingPosition.1 * 100
                        
                        updatedReadingPosition.lastReadPage = readerVC.updatedReadingPosition.2["pageNumber"] as? Int ?? 1
                        updatedReadingPosition.lastPosition[0] = readerVC.updatedReadingPosition.2["pageNumber"] as? Int ?? 1
                        updatedReadingPosition.lastPosition[1] = readerVC.updatedReadingPosition.2["pageOffsetX"] as? Int ?? 0
                        updatedReadingPosition.lastPosition[2] = readerVC.updatedReadingPosition.2["pageOffsetY"] as? Int ?? 0
                        
                        updatedReadingPosition.lastReadChapter = readerVC.updatedReadingPosition.3
                        
                        updatedReadingPosition.readerName = ReaderType.ReadiumCBZ.rawValue
                        
                        modelData.updatedReadingPosition = updatedReadingPosition
                    }))
                    
                    readerVC.moduleDelegate = moduleDelegate
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

class YabrEBookReaderModuleDelegate: ReaderFormatModuleDelegate {
    private let factory = ReaderFactory()
    
    func presentOutline(of publication: Publication, delegate: OutlineTableViewControllerDelegate?, from viewController: UIViewController) {
        let outlineTableVC: OutlineTableViewController = factory.make(publication: publication)
        outlineTableVC.delegate = delegate
        viewController.present(UINavigationController(rootViewController: outlineTableVC), animated: true)
    }
    
    func presentDRM(for publication: Publication, from viewController: UIViewController) {
        
    }
    
    func presentAlert(_ title: String, message: String, from viewController: UIViewController) {
        
    }
    
    func presentError(_ error: Error?, from viewController: UIViewController) {
        
    }
    
    
}
