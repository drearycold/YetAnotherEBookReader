//
//  BookView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import Foundation
import OSLog
import SwiftUI
import RealmSwift
import struct Kingfisher.KFImage

struct BookDetailViewRealm: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.openURL) var openURL
    
    @ObservedRealmObject var book: CalibreBookRealm
    
    var viewMode: BookDetailViewMode
    
    @StateObject private var previewViewModel = BookPreviewViewModel()
    
    var defaultLog = Logger()
    
    @State private var alertItem: AlertItem?

    @State private var updater = 0
    
    @State private var presentingReadingSheet = false {
        willSet { if newValue { modelData.presentingStack.append($presentingReadingSheet) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var presentingPreviewSheet = false {
        willSet { if newValue { modelData.presentingStack.append($presentingPreviewSheet) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var activityListViewPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($activityListViewPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }

    @State private var readingPositionHistoryViewPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($readingPositionHistoryViewPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @StateObject private var _viewModel = BookDetailViewModel()
    
    var body: some View {
        
        if let book = modelData.convert(bookRealm: book) {
            ScrollView {
                viewContent(book: book, isCompat: sizeClass == .compact)
                    .onAppear() {
                        modelData.calibreServerService.getMetadata(oldbook: book, completion: initStates(book:))
                    }
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    .navigationTitle(Text(book.title))
            }
            .toolbar {
                toolbarContent(book: book)
            }
            .alert(item: $alertItem) { item in
                return Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
            }
        } else {
            EmptyView()
        }
        
    }
    
    @ViewBuilder
    private func viewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .center) {
            
            #if canImport(GoogleMobileAds)
            #if GAD_ENABLED
            Banner()
            #endif
            #endif
            
            if isCompat {
                VStack(alignment: .center, spacing: 16) {
                    coverViewContent(book: book)
                    
                    metadataViewContent(book: book, isCompat: isCompat)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    connectivityViewContent(book: book, isCompat: isCompat)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    bookFormatViewContent(book: book, isCompat: isCompat)
                        .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    
                    if let countPage = book.library.pluginCountPagesWithDefault, countPage.isEnabled() {
                        countPagesCorner(book: book, countPage: countPage, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 32) {
                    coverViewContent(book: book)
                    VStack(alignment: .leading, spacing: 16) {
                        metadataViewContent(book: book, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        connectivityViewContent(book: book, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        bookFormatViewContent(book: book, isCompat: isCompat)
                            .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        
                        if let countPage = book.library.pluginCountPagesWithDefault, countPage.isEnabled() {
                            countPagesCorner(book: book, countPage: countPage, isCompat: isCompat)
                                .frame(minWidth: 300, maxWidth: 300, alignment: .leading)
                        }
                    }
                }
            }
            
            #if canImport(GoogleMobileAds)
            #if GAD_ENABLED
            Banner()
            #endif
            #endif
            
            WebViewUI(
                content: book.comments,
                baseURL: book.commentBaseURL
            )
            .frame(maxWidth: isCompat ? 400 : 600, minHeight: 400, maxHeight: 400, alignment: .center)
            
        }   //VStack
        //.fixedSize()
    }
    
    @ViewBuilder
    private func coverViewContent(book: CalibreBook) -> some View {
        ZStack {
            KFImage(book.coverURL)
                .placeholder {
                    Text("Loading Cover ...")
                }
                .resizable()
                .scaledToFit()
            Button(action: {
                guard modelData.activeDownloads.filter( {$1.isDownloading && $1.book.id == book.id} ).isEmpty else { return }
                
                if book.inShelf {
                    modelData.readerInfo = modelData.prepareBookReading(book: book)
                    presentingReadingSheet = true
                } else {
                    //TODO prompt for formats
                    if let downloadFormat = modelData.getPreferredFormat(for: book) {
                        modelData.addToShelf(book: book, formats: [downloadFormat])
                    } else {
                        alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
                    }
                }
            }) {
                if modelData.activeDownloads.filter( { $1.book.id == book.id && ($1.isDownloading || $1.resumeData != nil) } ).isEmpty == false ||
                    book.formats.filter({ $0.value.selected == true && $0.value.cached == false }).isEmpty == false
                {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                        .scaleEffect(6, anchor: .center)
                } else if book.inShelf,
                          book.formats.allSatisfy({ $1.selected != true || $1.cached }) {
                    Image(systemName: "book")
                        .resizable()
                        .frame(width: 160, height: 160)
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "tray.and.arrow.down")
                        .resizable()
                        .frame(width: 160, height: 160)
                        .foregroundColor(.gray)
                }
                
            }
            .opacity(0.8)
            .fullScreenCover(isPresented: $presentingReadingSheet) {
                YabrEBookReader(
                    book: book,
                    readerInfo: modelData.prepareBookReading(book: book)
                )
            }
        }
        .frame(width: 300, height: 400)
    }
    
    @ViewBuilder
    private func metadataViewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                metadataIcon(systemName: "building.columns")
                Text("\(book.library.name) - \(book.id) @ Server \(book.library.server.name)")
            }
            HStack {
                metadataIcon(systemName: "face.smiling")
                Text(book.ratingDescription)
                if let ratingGRDescription = book.ratingGRDescription {
                    Text(" (\(ratingGRDescription))")
                }
            }
            HStack {
                if book.authors.count <= 1 {
                    metadataIcon(systemName: "person")
                } else if book.authors.count == 2 {
                    metadataIcon(systemName: "person.2")
                } else {
                    metadataIcon(systemName: "person.3")
                }
                Text(book.authorsDescription)
            }
            HStack {
                metadataIcon(systemName: "house")
                Text(book.publisher)
            }
            HStack {
                metadataIcon(systemName: "calendar")
                Text(book.pubDateByLocale)
            }
            HStack {
                metadataIcon(systemName: "tray.2")
                Text("\(book.seriesDescription) (\(book.seriesIndexDescription))")
            }
            
            HStack {
                metadataIcon(systemName: "tag")
                Text(book.tagsDescription)
            }
            
            HStack {
                metadataIcon(systemName: "link")
                
                Button(action:{
                    var url: URL? = nil
                    defer {
                        if let url = url {
                            openURL(url)
                        }
                    }
                    
                    if let goodreadsId = book.identifiers["goodreads"] {
                       url = URL(string: "https://www.goodreads.com/book/show/\(goodreadsId)")
                    } else if var urlComponents = URLComponents(string: "https://www.goodreads.com/search") {
                        urlComponents.queryItems = [URLQueryItem(name: "q", value: book.title + " " + book.authors.joined(separator: " "))]
                        url = urlComponents.url
                    }
                }) {
                    metadataLinkIcon("icon-goodreads", matched: book.identifiers["goodreads"] != nil)
                }
                
                Button(action:{
                    var url: URL? = nil
                    defer {
                        if let url = url {
                            openURL(url)
                        }
                    }
                    
                    if let id = book.identifiers["amazon"] {
                       url = URL(string: "http://www.amazon.com/dp/\(id)")
                    } else if var urlComponents = URLComponents(string: "https://www.amazon.com/s") {
                        urlComponents.queryItems = [URLQueryItem(name: "k", value: book.title + " " + book.authors.joined(separator: " "))]
                        url = urlComponents.url
                    }
                }) {
                    metadataLinkIcon("icon-amazon", matched: book.identifiers["amazon"] != nil)
                }
                
            }
            
            Group {     // lastModified readDate(GR) ShelfName
                HStack {
                    metadataIcon(systemName: "envelope.open")
                    Text(book.lastModifiedByLocale)
                }
                
                progressView(book: book, isCompat: isCompat)
                
                HStack {
                    metadataIcon(systemName: "books.vertical")
                    if let pluginGoodreadsSync = book.library.pluginGoodreadsSyncWithDefault,
                       pluginGoodreadsSync.isEnabled(), pluginGoodreadsSync.tagsColumnName.count > 0,
                       let shelves = book.userMetadatas[pluginGoodreadsSync.tagsColumnName] as? [String],
                       shelves.count > 0 {
                        Text(shelves.joined(separator: ", "))
                    } else {
                        Text("Unspecified")
                    }
                }
            }
        }
        .lineLimit(2)
        .font(.subheadline)
        
    }
    
    @ViewBuilder
    private func progressView(book: CalibreBook, isCompat: Bool) -> some View {
        HStack {
            metadataIcon(systemName: "text.book.closed")
            
            Button(action:{
                if _viewModel.listVM == nil {
                    _viewModel.listVM = ReadingPositionListViewModel(
                        modelData: modelData, book: book, positions: book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
                    )
                } else {
                    _viewModel.listVM.book = book
                    _viewModel.listVM.positions = book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
                }
                readingPositionHistoryViewPresenting = true
            }) {
                if let readDateGR = book.readDateGRByLocale {
                    Image(systemName: "arrow.down.to.line")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                    Text(readDateGR)
                } else if let readProgressGR = book.readProgressGRDescription {
                    Image(systemName: "hourglass")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                    Text("\(readProgressGR)%")
                } else if let position = book.readPos.getPosition(modelData.deviceName) ?? book.readPos.getDevices().first {
                    Image(systemName: "book.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                    Text(String(format: "%.1f%%", position.lastProgress))
                    Text("on")
                    Text(position.id)
                } else {
                    Text("No Reading History")
                }
            }.disabled(book.readPos.isEmpty)
        }.sheet(isPresented: $readingPositionHistoryViewPresenting, onDismiss: {
            readingPositionHistoryViewPresenting = false
        }, content: {
            NavigationView {
                ReadingPositionHistoryView(presenting: $readingPositionHistoryViewPresenting, library: book.library, bookId: book.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction, content: {
                            Button(action: {
                                readingPositionHistoryViewPresenting = false
                            }) {
                                Image(systemName: "xmark")
                            }
                        })
                    }
            }
        })
    }
    
    @ViewBuilder
    private func connectivityViewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if modelData.updatingMetadataStatus == "Success" {
                HStack {
                    metadataIcon(systemName: "checkmark.shield")
                    Text("In Sync with Server")
                }
            } else if modelData.updatingMetadataStatus == "Local File" {
                HStack {
                    metadataIcon(systemName: "doc")
                    Text("Local File")
                }
            } else if modelData.updatingMetadataStatus == "Deleted" {
                HStack {
                    metadataIcon(systemName: "xmark.shield")
                    Text("Been Deleted on Server")
                }
            } else if modelData.updatingMetadataStatus == "Updating" {
                HStack {
                    metadataIcon(systemName: "arrow.clockwise")
                    Text("Syncing with Server")
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action:{
                        alertItem = AlertItem(id: "Sync Error", msg: modelData.updatingMetadataStatus)
                    }) {
                        HStack {
                            metadataIcon(systemName: "exclamationmark.shield")
                            Text("Sync Error Encounted")
                        }
                    }
                    
                }
            }
            HStack {
                metadataIcon(systemName: "scroll")
                Button(action: {
                    activityListViewPresenting = true
                }) {
                    Text("Activity Logs")
                }.sheet(isPresented: $activityListViewPresenting, onDismiss: {
                    
                }, content: {
                    NavigationView {
                        ActivityList(presenting: $activityListViewPresenting, libraryId: book.library.id, bookId: book.id)
                            .environmentObject(modelData)
                    }
                })
            }
            
        }

    }
    
    @ViewBuilder
    private func metadataIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 24, alignment: .center)
    }
    
    @ViewBuilder
    private func metadataLinkIcon(_ name: String, matched: Bool = false) -> some View {
        HStack(alignment: .top, spacing: -2) {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            if matched == false {
                Image(systemName: "questionmark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    @ViewBuilder
    private func metadataFormatIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
    }
    
    @ViewBuilder
    private func countPagesCorner(book: CalibreBook, countPage: CalibreLibraryCountPages, isCompat: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Count Pages Info Corner")
            HStack {
                Text("Pages \(book.userMetadataNumberAsIntDescription(column: countPage.pageCountCN) ?? "not set")")
                Text("/").padding([.leading, .trailing], 16)
                Text("Words \(book.userMetadataNumberAsIntDescription(column: countPage.wordCountCN) ?? "not set")")
                
            }.font(.subheadline)
            HStack {
                Text("Readability \(book.userMetadataNumberAsFloatDescription(column: countPage.fleschReadingEaseCN) ?? "not set") / \(book.userMetadataNumberAsFloatDescription(column: countPage.fleschKincaidGradeCN) ?? "not set") / \(book.userMetadataNumberAsFloatDescription(column: countPage.gunningFogIndexCN) ?? "not set")")
            }.font(.subheadline)
        }
    }
    
    @ViewBuilder
    private func bookFormatViewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(book.formats.sorted {
                $0.key < $1.key
            }.compactMap {
                if let format = Format(rawValue: $0.key) {
                    return (format, $0.value)
                }
                return nil
            } as [(Format, FormatInfo)], id: \.0) { format, formatInfo in
                HStack(alignment: .top, spacing: 4) {
                    metadataFormatIcon(
                        format.rawValue
                    )
                    .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .bottom, spacing: 24) {
                            Text(format.rawValue)
                                .font(.subheadline)
                                .frame(minWidth: 48, alignment: .leading)
                            cacheFormatButton(
                                book: book,
                                format: format,
                                formatInfo: formatInfo
                            ).disabled(modelData.activeDownloads.filter( { $1.book.id == book.id && $1.format == format && ($1.isDownloading || $1.resumeData != nil) } ).count > 0)
                            
                            clearFormatButton(
                                book: book,
                                format: format,
                                formatInfo: formatInfo
                            ).disabled(!formatInfo.cached)
                            
                            previewFormatButton(
                                book: book,
                                format: format,
                                formatInfo: formatInfo
                            ).disabled(!formatInfo.cached)
                        }
                        HStack {
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: Int64(formatInfo.serverSize),
                                    countStyle: .file
                                )
                            )
                            if let download = modelData.activeDownloads.filter( { $1.book.id == book.id && $1.format == format && ($1.isDownloading || $1.resumeData != nil) } ).first?.value {
                                ProgressView(value: download.progress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(maxWidth: 160)
                                
                                Button(action: {
                                    if download.isDownloading {
                                        modelData.pauseDownloadFormat(book: book, format: format)
                                    } else {
                                        modelData.resumeDownloadFormat(book: book, format: format)
                                    }
                                    
                                }) {
                                    Image(systemName: download.isDownloading ? "pause" : "play")
                                }
                                
                                //cancel download
                                Button(action:{
                                    modelData.cancelDownloadFormat(book: book, format: format)
                                }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(.red)
                                }
                            } else if formatInfo.cached {
                                Text(formatInfo.cacheUptoDate ? "Up to date" : "Server has update")
                                Image(systemName: formatInfo.cacheUptoDate ? "hand.thumbsup" : "hand.thumbsdown")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                            } else {
                                Text("Not cached")
                            }
                        }
                        .font(.caption)
                    }
                    
                }
            }
        }
    }
    
    private func cacheFormatButton(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> some View {
        Button(action:{
            if book.inShelf {
                modelData.startDownloadFormat(
                    book: book,
                    format: format,
                    overwrite: true
                )
            } else {
                modelData.addToShelf(book: book, formats: [format])
            }
        }) {
            Image(systemName: "tray.and.arrow.down")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    private func clearFormatButton(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> some View {
        Button(action:{
            modelData.clearCache(book: book, format: format)
        }) {
            Image(systemName: "tray.and.arrow.up")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    private func previewFormatButton(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> some View {
        Button(action: {
            guard let reader = modelData.formatReaderMap[format]?.first else { return }
            previewAction(book: book, format: format, formatInfo: formatInfo, reader: reader)
        }) {
            Image(systemName: "doc.text.magnifyingglass")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
        .sheet(isPresented: $presentingPreviewSheet, onDismiss: {
            modelData.readerInfo = modelData.prepareBookReading(book: book)
        }) {
            BookPreviewView(viewModel: previewViewModel)
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent(book: CalibreBook) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                if modelData.updatingMetadata {
                    //TODO cancel
                } else {
                    if let coverUrl = book.coverURL {
                        modelData.kfImageCache.removeImage(forKey: coverUrl.absoluteString)
                    }
                    modelData.calibreServerService.getMetadata(oldbook: book, completion: initStates(book:))
                }
            }) {
                if modelData.updatingMetadata {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                if book.inShelf {
                    modelData.clearCache(inShelfId: book.inShelfId)
                } else if modelData.activeDownloads.filter( {$1.isDownloading && $1.book.id == book.id} ).isEmpty {
                    //TODO prompt for formats
                    if let downloadFormat = modelData.getPreferredFormat(for: book) {
                        modelData.addToShelf(book: book, formats: [downloadFormat])
                    } else {
                        alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
                    }
                }
                updater += 1
            }) {
                if let download = modelData.activeDownloads.filter( {$1.isDownloading && $1.book.id == book.id} ).first {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else if book.inShelf {
                    Image(systemName: "star.slash")
                } else {
                    Image(systemName: "star")
                }
            }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                readingPositionHistoryViewPresenting = true
            }) {
                Image(systemName: "clock")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
        }
    }
    
    func initStates(book: CalibreBook) {
        if _viewModel.listVM == nil {
            _viewModel.listVM = ReadingPositionListViewModel(
                modelData: modelData, book: book, positions: book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
            )
        } else {
            _viewModel.listVM.book = book
            _viewModel.listVM.positions = book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
        }
        
//        modelData.calibreServerService.getAnnotations(
//            book: book,
//            formats: book.formats.keys.compactMap { Format(rawValue: $0) }
//        )
    }
    
    func previewAction(book: CalibreBook, format: Format, formatInfo: FormatInfo, reader: ReaderType) {
        guard let bookFileUrl = getSavedUrl(book: book, format: format)
        else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return
        }
        
        let readPosition = book.readPos.createInitial(deviceName: modelData.deviceName, reader: reader)
        
        modelData.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: reader,
            position: readPosition
        )
        
        previewViewModel.modelData = modelData
        previewViewModel.book = book
        previewViewModel.url = bookFileUrl
        previewViewModel.format = format
        previewViewModel.reader = reader
        previewViewModel.toc = "Initializing"
        
        modelData.calibreServerService.getBookManifest(book: book, format: format) { data in
            guard let data = data else { return }
            self.parseManifestToTOC(json: data)
        }
        
        presentingPreviewSheet = true
    }
    
    func parseManifestToTOC(json: Data) {
        previewViewModel.toc = "Without TOC"
        
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            #if DEBUG
            previewViewModel.toc = String(data: json, encoding: .utf8) ?? "String Decoding Failure"
            #endif
            return
        }
        
        guard let tocNode = root["toc"] as? NSDictionary else {
            #if DEBUG
            previewViewModel.toc = String(data: json, encoding: .utf8) ?? "String Decoding Failure"
            #endif
            
            if let jobStatus = root["job_status"] as? String, jobStatus == "waiting" || jobStatus == "running" {
                previewViewModel.toc = "Generating TOC, Please try again later"
            }
            return
        }
        
        guard let childrenNode = tocNode["children"] as? NSArray else {
            return
        }
        
        let tocString = childrenNode.reduce(into: String()) { result, childNode in
            result = result + ((childNode as! NSDictionary)["title"] as! String) + "\n"
        }
        
        previewViewModel.toc = tocString
    }
    
    func handleBookDeleted() {
//        modelData.libraryInfo.deleteBook(book: book)
        //TODO
        //getMetadata()
    }
    
    func generateCommentWithTOC(comments: String, toc: String) -> String {
        let lines = toc.split(separator: "\n")
        let tocHTML = lines.reduce("<div><b>Table of Content</b><ul>\n") { result, line in
            result.appending("<li>").appending(line).appending("</li>").appending("\n")
        }.appending("</ul></div>\n")
        
        return comments + "\n" + tocHTML
    }
}

extension BookDetailViewRealm : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

@available(macCatalyst 14.0, *)
struct BookDetailViewRealm_Previews: PreviewProvider {
    static var modelData = ModelData(mock: true)
     
    static var previews: some View {
        BookDetailView(viewMode: .LIBRARY)
            .environmentObject(modelData)
    }
}
