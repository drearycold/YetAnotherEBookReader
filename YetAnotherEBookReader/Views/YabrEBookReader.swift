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
struct YabrEBookReader: UIViewControllerRepresentable {
    
    let book: CalibreBook
    let readerInfo: ReaderInfo
    
    let moduleDelegate = YabrEBookReaderModuleDelegate()
    
    @EnvironmentObject var modelData: ModelData
    
    init(book: CalibreBook, readerInfo: ReaderInfo) {
        self.book = book
        self.readerInfo = readerInfo
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        defer {
            modelData.logBookDeviceReadingPositionHistoryStart(book: book, position: readerInfo.position, startDatetime: Date())
        }
        let nav = YabrEBookReaderNavigationController(modelData: modelData, book: book, readerInfo: readerInfo)
        nav.modelData = modelData
        nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        nav.navigationBar.isTranslucent = false
        nav.setToolbarHidden(false, animated: true)

//        #if canImport(R2Shared)
        if (readerInfo.format == Format.EPUB && readerInfo.readerType == ReaderType.ReadiumEPUB)
            || (readerInfo.format == Format.PDF && readerInfo.readerType == ReaderType.ReadiumPDF)
            || (readerInfo.format == Format.CBZ && readerInfo.readerType == ReaderType.ReadiumCBZ) {
            guard let server = PublicationServer() else {
                return nav
            }
            
            let streamer = Streamer()
            
            let asset = FileAsset(url: readerInfo.url)
            
            streamer.open(asset: asset, allowUserInteraction: true) { result in
                do {
                    let publication = try result.get()
                    server.removeAll()
                    try server.add(publication)
                    let book = Book(
                        href: self.readerInfo.url.lastPathComponent,
                        title: publication.metadata.title,
                        author: publication.metadata.authors.map{$0.name}.joined(separator: ", "),
                        identifier: publication.metadata.identifier ?? self.readerInfo.url.deletingPathExtension().lastPathComponent,
                        cover: publication.cover?.pngData()
                    )
                    
                    //readingOrder for EPUB & CBZ, metadata.numberOfPages for PDF
                    if self.readerInfo.position.lastReadPage > 0,
                       self.readerInfo.readerType == ReaderType.ReadiumPDF ? self.readerInfo.position.lastReadPage - 1 < publication.metadata.numberOfPages ?? 0 : self.readerInfo.position.lastReadPage - 1 < publication.readingOrder.count,
                       let link = self.readerInfo.readerType == ReaderType.ReadiumPDF ? publication.readingOrder.first : publication.readingOrder[self.readerInfo.position.lastReadPage - 1] {
                        let locator = Locator(
                            href: link.href,
                            type: link.type ?? "",
                            title: self.readerInfo.position.lastReadChapter,
                            locations: Locator.Locations(
                                fragments: [],
                                progression: self.readerInfo.position.lastChapterProgress / 100.0,
                                totalProgression: self.readerInfo.position.lastProgress / 100.0,
                                position: self.readerInfo.readerType == ReaderType.ReadiumPDF ? self.readerInfo.position.lastPosition[0] : self.readerInfo.position.lastPosition[1],
                                otherLocations: [:]),
                            text: Locator.Text())
                        book.progression = locator.jsonString
                    }
                    
                    guard let readerVC = { () -> YabrReadiumReaderViewController? in
                        switch(self.readerInfo.readerType) {
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
                    
                    readerVC.readerType = self.readerInfo.readerType
                    readerVC.readPos = self.book.readPos
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
        
        if readerInfo.format == Format.PDF {
            let dictViewer = modelData.getCustomDictViewerNew(library: book.library)
            _ = modelData.updateCustomDictViewer(enabled: dictViewer.0, value: dictViewer.1?.absoluteString)
            
            let pdfViewController = YabrPDFViewController()
            let ret = pdfViewController.open(pdfURL: readerInfo.url, position: readerInfo.position)
            if ret == 0 {
                nav.pushViewController(pdfViewController, animated: false)
                return nav
            } else {
                
            }
        }
        
        if readerInfo.format == Format.EPUB {
            let readerConfiguration = EpubFolioReaderContainer.Configuration(bookURL: readerInfo.url)

            let dictViewer = modelData.getCustomDictViewerNew(library: book.library)
            _ = modelData.updateCustomDictViewer(enabled: dictViewer.0, value: dictViewer.1?.absoluteString)
            
            readerConfiguration.enableMDictViewer = dictViewer.0
            readerConfiguration.userFontDescriptors = modelData.userFontInfos.mapValues { $0.descriptor }
            
//            readerConfiguration.hideBars = true
//            readerConfiguration.hidePageIndicator = true
//            readerConfiguration.shouldHideNavigationOnTap = true
            
            let folioReader = FolioReader()
            let epubReaderContainer = EpubFolioReaderContainer(withConfig: readerConfiguration, folioReader: folioReader, epubPath: readerInfo.url.path)
            
            epubReaderContainer.modelData = modelData
            epubReaderContainer.open(bookReadingPosition: readerInfo.position)
            
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

    func updateReadingPosition(readPos: BookReadingPosition, position: BookDeviceReadingPosition)
}
