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
//#if canImport(R2Shared)
import R2Shared
import R2Streamer
//#endif

@available(macCatalyst 14.0, *)
struct YabrEBookReader: UIViewControllerRepresentable {
    
    let book: CalibreBook
    let bookURL : URL
    let bookFormat: Format
    let bookReader: ReaderType
    let bookPosition: BookDeviceReadingPosition
    
    let moduleDelegate = YabrEBookReaderModuleDelegate()
    
    @EnvironmentObject var modelData: ModelData
    
    init(book: CalibreBook, readerInfo: ReaderInfo) {
        self.book = book
        bookURL = readerInfo.url
        bookFormat = readerInfo.format
        bookReader = readerInfo.readerType
        bookPosition = readerInfo.position
    }
    
    init(book: CalibreBook, url: URL, format: Format, reader: ReaderType, position: BookDeviceReadingPosition) {
        self.book = book
        self.bookURL = url
        self.bookFormat = format
        self.bookReader = reader
        self.bookPosition = position
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        defer {
            modelData.logBookDeviceReadingPositionHistoryStart(book: book, startPosition: bookPosition, startDatetime: Date())
        }
        let nav = YabrEBookReaderNavigationController()
        nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        nav.navigationBar.isTranslucent = false
        nav.setToolbarHidden(false, animated: true)

//        #if canImport(R2Shared)
        if bookFormat == Format.EPUB && bookReader == ReaderType.ReadiumEPUB
            || bookFormat == Format.PDF && bookReader == ReaderType.ReadiumPDF
            || bookFormat == Format.CBZ && bookReader == ReaderType.ReadiumCBZ {
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
                    let book = Book(
                        href: bookURL.lastPathComponent,
                        title: publication.metadata.title,
                        author: publication.metadata.authors.map{$0.name}.joined(separator: ", "),
                        identifier: publication.metadata.identifier ?? bookURL.lastPathComponent,
                        cover: publication.cover?.pngData()
                    )
                    
                    //readingOrder for EPUB & CBZ, metadata.numberOfPages for PDF
                    if bookPosition.lastReadPage > 0,
                       bookReader == ReaderType.ReadiumPDF ? bookPosition.lastReadPage - 1 < publication.metadata.numberOfPages ?? 0 : bookPosition.lastReadPage - 1 < publication.readingOrder.count,
                       let link = bookReader == ReaderType.ReadiumPDF ? publication.readingOrder.first : publication.readingOrder[bookPosition.lastReadPage - 1] {
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: bookPosition.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: bookPosition.lastChapterProgress / 100.0,
                                totalProgression: bookPosition.lastProgress / 100.0,
                                position: bookReader == ReaderType.ReadiumPDF ? bookPosition.lastPosition[0] : bookPosition.lastPosition[1],
                                otherLocations: [:]),
                            text: Locator.Text())
                        book.progression = locator.jsonString
                    }
                    
                    guard let readerVC = { () -> YabrReadiumReaderViewController? in
                        switch(bookReader) {
                        case .ReadiumEPUB:
                            return YabrReadiumEPUBViewController(publication: publication, book: book, resourcesServer: server)
                        case .ReadiumPDF:
                            return YabrReadiumPDFViewController(publication: publication, book: book)
                        case .ReadiumCBZ:
                            return YabrReadiumCBZViewController(publication: publication, book: book)
                        default:
                            return nil      //shouldn't fall here
                        }
                    }() else { return }
                    
                    readerVC.readerType = bookReader
                    readerVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
                        systemItem: .close,
                        primaryAction: UIAction(
                            handler: { [self] _ in
                                modelData.updatedReadingPosition = readerVC.getUpdateReadingPosition(position: modelData.updatedReadingPosition)
                                
                                readerVC.dismiss(animated: true, completion: nil)
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
//        #endif
        
        if bookFormat == Format.PDF {
            let dictViewer = modelData.getCustomDictViewerNew(library: book.library)
            _ = modelData.updateCustomDictViewer(enabled: dictViewer.0, value: dictViewer.1?.absoluteString)
            
            let pdfViewController = YabrPDFViewController()
            let ret = pdfViewController.open(pdfURL: bookURL, position: bookPosition)
            if ret == 0 {
                nav.pushViewController(pdfViewController, animated: false)
                return nav
            } else {
                
            }
        }
        
        if bookFormat == Format.EPUB {
            let readerConfiguration = EpubFolioReaderContainer.Configuration(bookURL: bookURL)

            let dictViewer = modelData.getCustomDictViewerNew(library: book.library)
            _ = modelData.updateCustomDictViewer(enabled: dictViewer.0, value: dictViewer.1?.absoluteString)
            
            readerConfiguration.enableMDictViewer = dictViewer.0
            readerConfiguration.userFontDescriptors = modelData.userFontInfos.mapValues { $0.descriptor }
//            readerConfiguration.hideBars = true
//            readerConfiguration.hidePageIndicator = true
//            readerConfiguration.shouldHideNavigationOnTap = true
            
            let folioReader = FolioReader()
            let epubReaderContainer = EpubFolioReaderContainer(withConfig: readerConfiguration, folioReader: folioReader, epubPath: bookURL.path)
            
            epubReaderContainer.modelData = modelData
            epubReaderContainer.open(bookReadingPosition: bookPosition)
            
            nav.pushViewController(epubReaderContainer, animated: false)
            nav.setToolbarHidden(true, animated: false)
            nav.setNavigationBarHidden(true, animated: false)
            
            return nav
        }
        
        return nav
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

protocol YabrReadingPositionMaintainer {
    func getUpdateReadingPosition(position: BookDeviceReadingPosition) -> BookDeviceReadingPosition
}
