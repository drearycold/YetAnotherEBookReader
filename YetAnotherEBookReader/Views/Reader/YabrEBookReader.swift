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
import ReadiumShared
import ReadiumStreamer
import ReadiumAdapterGCDWebServer
import ReadiumGCDWebServer

@available(macCatalyst 14.0, *)
struct YabrEBookReader: View {
    let book: CalibreBook
    let readerInfo: ReaderInfo
    
    var body: some View {
        YabrEBookReaderRepresentable(book: book, readerInfo: readerInfo)
            .ignoresSafeArea()
    }
}

@available(macCatalyst 14.0, *)
struct YabrEBookReaderRepresentable: UIViewControllerRepresentable {
    
    let book: CalibreBook
    let readerInfo: ReaderInfo
    
    let errorViewController = UIViewController()
    let errorLabel = UILabel()
    
    @EnvironmentObject var modelData: ModelData
    
    init(book: CalibreBook, readerInfo: ReaderInfo) {
        self.book = book
        self.readerInfo = readerInfo
        
        errorViewController.view.addSubview(errorLabel)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let nav = YabrEBookReaderNavigationController(modelData: modelData, book: book, readerInfo: readerInfo)
        nav.modelData = modelData
        nav.modalPresentationStyle = UIModalPresentationStyle.fullScreen
        nav.navigationBar.isTranslucent = true

//        #if canImport(R2Shared)
        if (readerInfo.format == Format.EPUB && readerInfo.readerType == ReaderType.ReadiumEPUB)
            || (readerInfo.format == Format.PDF && readerInfo.readerType == ReaderType.ReadiumPDF)
            || (readerInfo.format == Format.CBZ && readerInfo.readerType == ReaderType.ReadiumCBZ) {
            
            
            let httpClient = DefaultHTTPClient()
            let assetRetriever = AssetRetriever(httpClient: httpClient)
            let httpServer = GCDHTTPServer(assetRetriever: assetRetriever)
            let readiumEnv = YabrReadiumEnvironment(httpClient: httpClient, assetRetriever: assetRetriever, httpServer: httpServer, book: self.book)
            
            let publicationOpener = PublicationOpener(
                parser: DefaultPublicationParser(httpClient: httpClient, assetRetriever: assetRetriever, pdfFactory: DefaultPDFDocumentFactory())
            )
            
            Task {
                guard let absoluteUrl = readerInfo.url.anyURL.absoluteURL,
                      let asset = try? await assetRetriever.retrieve(url: absoluteUrl).get() else { return }
                
                let result = await publicationOpener.open(asset: asset, allowUserInteraction: true)
                DispatchQueue.main.async {
                do {
                    let publication = try result.get()
                    var initialLocation: Locator? = nil
                    
                    //readingOrder for EPUB & CBZ, metadata.numberOfPages for PDF
                    if self.readerInfo.position.lastReadPage > 0,
                       self.readerInfo.readerType == ReaderType.ReadiumPDF ? self.readerInfo.position.lastReadPage - 1 < publication.metadata.numberOfPages ?? 0 : self.readerInfo.position.lastReadPage - 1 < publication.readingOrder.count,
                       let link = self.readerInfo.readerType == ReaderType.ReadiumPDF ? publication.readingOrder.first : publication.readingOrder[self.readerInfo.position.lastReadPage - 1] {
                        if let href = AnyURL(legacyHREF: link.href) {
                            initialLocation = Locator(
                                href: href,
                                mediaType: link.mediaType ?? .html,
                                title: self.readerInfo.position.lastReadChapter,
                                locations: Locator.Locations(
                                    fragments: [],
                                    progression: self.readerInfo.position.lastChapterProgress / 100.0,
                                    totalProgression: self.readerInfo.position.lastProgress / 100.0,
                                    position: self.readerInfo.readerType == ReaderType.ReadiumPDF ? self.readerInfo.position.lastPosition[0] : self.readerInfo.position.lastPosition[1],
                                    otherLocations: [:]),
                                text: Locator.Text())
                        }
                    }
                    
                    guard let readerVC = { () -> YabrReadiumReaderViewController? in
                        switch(self.readerInfo.readerType) {
                        case .ReadiumEPUB:
                            return YabrReadiumEPUBViewController(publication: publication, initialLocation: initialLocation, environment: readiumEnv)
                        case .ReadiumPDF:
                            return YabrReadiumPDFViewController(publication: publication, initialLocation: initialLocation, environment: readiumEnv)
                        case .ReadiumCBZ:
                            return YabrReadiumCBZViewController(publication: publication, initialLocation: initialLocation, environment: readiumEnv)
                        default:
                            return nil      //shouldn't fall here
                        }
                    }() else { return }
                    
                    readerVC.readiumMetaSource = YabrEBookReaderReadiumMetaSource(book: self.book, readerInfo: self.readerInfo)
                    readerVC.navigationItem.leftBarButtonItem = UIBarButtonItem(
                        systemItem: .close,
                        primaryAction: UIAction(
                            handler: { action in
                                if let locator = readerVC.navigator.currentLocation {
                                    readerVC.navigator(readerVC.navigator, locationDidChange: locator)
                                }
                                readerVC.dismiss(animated: true, completion: nil)
                            }
                        )
                    )
                    
                    nav.setToolbarHidden(true, animated: false)
                    nav.pushViewController(readerVC, animated: false)
                } catch {
                    print(error)
                }
                }
            }
            
            return nav
        }
//        #endif
        
        if readerInfo.format == Format.PDF {
            let dictViewer = modelData.getCustomDictViewerNew(library: book.library)
            _ = modelData.updateCustomDictViewer(enabled: dictViewer.0, value: dictViewer.1?.absoluteString)
            
            let pdfViewController = YabrPDFViewController()
            let metaSource = YabrEBookReaderPDFMetaSource(book: book, readerInfo: readerInfo)
            if dictViewer.0 {
                metaSource.dictViewerItem = "Lookup"
                metaSource.dictViewerNav.setViewControllers([metaSource.dictViewerTab], animated: false)
                
                metaSource.dictViewerNav.navigationBar.isTranslucent = false
                metaSource.dictViewerNav.isToolbarHidden = true
                
                if let options = metaSource.yabrPDFOptions(pdfViewController.pdfView) {
                    metaSource.updateDictViewerStyle(options: options)
                }
            }
            pdfViewController.yabrPDFMetaSource = metaSource
            let ret = pdfViewController.open()
            if ret == 0 {
                nav.pushViewController(pdfViewController, animated: false)
            } else {
                errorLabel.text = "Fail to open PDF, code=\(ret)"
                nav.pushViewController(errorViewController, animated: false)
            }
            
            nav.setToolbarHidden(false, animated: true)
            return nav
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
            let webServer = ReadiumGCDWebServer()

            guard let unzipPath = makeFolioReaderUnzipPath() else {
                return nav
            }
            
            let epubReaderContainer = EpubFolioReaderContainer(withConfig: readerConfiguration, folioReader: folioReader, epubPath: readerInfo.url.path, webServer: webServer)

            epubReaderContainer.modelData = modelData
            epubReaderContainer.open(bookReadingPosition: readerInfo.position)
            _ = epubReaderContainer.folioReaderPreferenceProvider(epubReaderContainer.folioReader).preference(listProfile: nil)
            
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
