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

enum DownloadStatus: String, CaseIterable, Identifiable {
    case INITIAL
    case DOWNLOADING
    case DOWNLOADED
    
    var id: String { self.rawValue }
}

enum BookDetailViewMode: String, CaseIterable, Identifiable {
    case SHELF
    case LIBRARY
    
    var id: String { self.rawValue }
}

@available(macCatalyst 14.0, *)
struct BookDetailView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.openURL) var openURL
    
    var viewMode: BookDetailViewMode
    
    @StateObject private var previewViewModel = BookPreviewViewModel()
    
    @State private var downloadStatus = DownloadStatus.INITIAL
    
    var defaultLog = Logger()
    
    @State private var alertItem: AlertItem?

    @State private var updater = 0
    
    @State private var presentingReadSheet = false {
        willSet { if newValue { modelData.presentingStack.append($presentingReadSheet) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var presentingReadPositionList = false {
        willSet { if newValue { modelData.presentingStack.append($presentingReadPositionList) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    @State private var activityListViewPresenting = false {
        willSet { if newValue { modelData.presentingStack.append($activityListViewPresenting) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }

    @State private var shelfNameShowDetail = false
    @State private var shelfName = ""
    @State private var shelfNameCustomized = false
    
    @StateObject private var _viewModel = BookDetailViewModel()
    
    var body: some View {
        ScrollView {
            if let book = modelData.readingBook {
                viewContent(book: book, isCompat: sizeClass == .compact)
                .onAppear() {
                    modelData.calibreServerService.getMetadata(oldbook: book, completion: initStates(book:))
                }
                .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                .navigationTitle(Text(book.title))
                .sheet(isPresented: $presentingReadSheet, onDismiss: { presentingReadSheet = false }) {
                    BookPreviewView(viewModel: previewViewModel)
                }
            } else {
                EmptyView()
            }
        }
        .toolbar {
            toolbarContent()
        }
        .onChange(of: modelData.readingBook) {book in
            if let book = book {
                modelData.calibreServerService.getMetadata(oldbook: book, completion: initStates(book:))
            }
        }
        .onChange(of: downloadStatus) { value in
            if downloadStatus == .DOWNLOADED {
                modelData.addToShelf(modelData.readingBook!.id, shelfName: shelfName)
            }
        }
        .alert(item: $alertItem) { item in
            if item.id == "Delete" {
                return Alert(
                    title: Text("Confirm to Deleting"),
                    message: Text("Will Delete Book from Calibre Server"),
                    primaryButton: .destructive(Text("Sure"), action: {
                        deleteBook()
                    }),
                    secondaryButton: .cancel()
                )
            }
            if item.id == "Updated" {
                return Alert(title: Text("Updated"), message: Text(item.msg ?? "Success"))
            }
            return Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .disabled(modelData.readingBook == nil)
    }
    
    @ViewBuilder
    private func viewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .center) {
            
            #if canImport(GoogleMobileAds)
            Banner()
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
                    }
                }
            }
            
            #if canImport(GoogleMobileAds)
            Banner()
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
                if _viewModel.listVM == nil {
                    _viewModel.listVM = ReadingPositionListViewModel(
                        modelData: modelData, book: book, positions: book.readPos.getDevices()
                    )
                } else {
                    _viewModel.listVM.book = book
                    _viewModel.listVM.positions = book.readPos.getDevices()
                }
                presentingReadPositionList = true
            }) {
                Image(systemName: "book")
                    .resizable()
                    .frame(width: 150, height: 150)
                    .foregroundColor(.gray)
                
            }.disabled(book.inShelf == false)
            .opacity(book.inShelf ? 0.6 : 0.0)
        }
        .frame(width: 300, height: 400)
    }
    
    @ViewBuilder
    private func metadataViewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Text(book.seriesDescription)
            }
            
            HStack {
                metadataIcon(systemName: "tag")
                Text(book.tagsDescription)
            }
            
            HStack {
                metadataIcon(systemName: "link")
                
                Button(action:{
                    if let goodreadsId = book.identifiers["goodreads"],
                       let url = URL(string: "https://www.goodreads.com/book/show/\(goodreadsId)") {
                        openURL(url)
                    } else if var urlComponents = URLComponents(string: "https://www.goodreads.com/search") {
                        urlComponents.queryItems = [URLQueryItem(name: "q", value: book.title + " " + book.authors.joined(separator: " "))]
                        if let url = urlComponents.url {
                            openURL(url)
                        }
                    }
                }) {
                    metadataLinkIcon("icon-goodreads")
                }
                
                if let id = book.identifiers["amazon"] {
                    Button(action:{
                        openURL(URL(string: "http://www.amazon.com/dp/\(id)")!)
                    }) {
                        metadataLinkIcon("icon-amazon")
                    }
                } else {
                    Button(action:{
                        openURL(URL(string: "https://www.amazon.com/")!)
                    }) {
                        metadataLinkIcon("icon-amazon")
                    }.hidden()
                }
            }
            
            Group {     // lastModified readDate(GR) ShelfName
                HStack {
                    metadataIcon(systemName: "envelope.open")
                    Text(book.lastModifiedByLocale)
                }
                
                
                HStack {
                    metadataIcon(systemName: "text.book.closed")
                    if let readDateGR = book.readDateGRByLocale {
                        Text("\(Image(systemName: "arrow.down.to.line")) \(readDateGR)")
                    } else if let readProgressGR = book.readProgressGRDescription {
                        Text("\(Image(systemName: "hourglass")) \(readProgressGR)%")
                    } else {
                        Text("\(Image(systemName: "book.circle")) \(Int(modelData.getSelectedReadingPosition(book: book)?.lastProgress ?? 0.0))%")
                    }
                }
                
                HStack {
                    metadataIcon(systemName: "books.vertical")
                    if shelfNameCustomized {
                        TextField("Shelf Name", text: $shelfName)
                    } else {
                        Picker(shelfName, selection: $shelfName) {
                            ForEach(book.tags, id:\.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        
                    }
                    
                    Button(action: { shelfNameShowDetail.toggle() } ) {
                        if shelfNameShowDetail {
                            Image(systemName: "chevron.up")
                        } else {
                            Image(systemName: "chevron.down")
                        }
                    }
                    
                    if book.tags.count > 1 {
                        Text("(\(book.tags.count))")
                    }
                }
                .onChange(of: shelfName) { value in
                    modelData.readingBook!.inShelfName = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    modelData.updateBook(book: modelData.readingBook!)
                }
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
                
                if shelfNameShowDetail {
                    HStack {
                        metadataIcon(systemName: "books.vertical").hidden()
                        Toggle("Customize Shelf Name", isOn: $shelfNameCustomized)
                    }
                }
            }
        }
        .lineLimit(2)
        .font(.subheadline)
        
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
                        ActivityList(libraryId: book.library.id, bookId: book.id)
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
    private func metadataLinkIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
    }
    
    @ViewBuilder
    private func metadataFormatIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
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
                            )
                            
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
                            if formatInfo.cached {
                                Text(formatInfo.cacheUptoDate ? "Up to date" : "Server has update")
                                Image(systemName: formatInfo.cacheUptoDate ? "hand.thumbsup" : "hand.thumbsdown")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                            } else if let download = modelData.activeDownloads.filter( { $1.book.id == book.id && $1.format == format && ($1.isDownloading || $1.resumeData != nil) } ).first?.value {
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
                            }
                            else {
                                Text("Not cached")
                            }
                        }
                        .font(.caption)
                    }
                    
                }
            }
        }
        .sheet(isPresented: $presentingReadPositionList, onDismiss: {
            print("ReadingPositionListView dismiss \(book.readPos.getDevices().count) \(_viewModel.listVM.book.readPos.getDevices().count)")
            guard book.readPos.getDevices().count != _viewModel.listVM.book.readPos.getDevices().count else { return }
            modelData.updateReadingPosition(book: _viewModel.listVM.book, alertDelegate: self)
        }) {
            ReadingPositionListView(viewModel: _viewModel.listVM)
        }
    }
    
    private func cacheFormatButton(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> some View {
        Button(action:{
            modelData.clearCache(book: book, format: format)
            modelData.startDownloadFormat(
                book: book,
                format: format
            )
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
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
//        ToolbarItem(placement: .cancellationAction) {
//            Button(action: {
//                alertItem = AlertItem(id: "Delete")
//            }) {
//                if viewMode == .LIBRARY {
//                Image(systemName: "trash")
//                    .accentColor(.red)
//                } else {
//                    EmptyView().hidden()
//                }
//            }.disabled(!modelData.updatingMetadataSucceed)
//        }
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                if modelData.updatingMetadata {
                    //TODO cancel
                } else {
                    if let book = modelData.readingBook {
                        if let coverUrl = book.coverURL {
                            modelData.kfImageCache.removeImage(forKey: coverUrl.absoluteString)
                        }
                        modelData.calibreServerService.getMetadata(oldbook: book, completion: initStates(book:))
                    }
                }
            }) {
                if viewMode == .SHELF {
                    if modelData.updatingMetadata {
                        Image(systemName: "xmark")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                } else {
                    EmptyView().hidden()
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                modelData.goToPreviousBook()
            }) {
                if viewMode == .LIBRARY && sizeClass == .regular {
                    Image(systemName: "chevron.up")
                } else {
                    Image(systemName: "chevron.up").hidden()
                }
            }
            .disabled(!modelData.updatingMetadataSucceed)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                modelData.goToNextBook()
            }) {
                if viewMode == .LIBRARY && sizeClass == .regular {
                    Image(systemName: "chevron.down")
                } else {
                    Image(systemName: "chevron.down").hidden()
                }
            }.disabled(!modelData.updatingMetadataSucceed)
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                guard let book = modelData.readingBook else {
                    assert(false, "modelData.readingBook is nil")
                    return
                }
                if book.inShelf {
                    modelData.clearCache(inShelfId: book.inShelfId)
                    downloadStatus = .INITIAL
                } else if modelData.activeDownloads.filter( {$1.isDownloading && $1.book.id == book.id} ).isEmpty {
                    //TODO prompt for formats
                    if let downloadFormat = modelData.getPreferredFormat(for: book), modelData.startDownloadFormat(book: book, format: downloadFormat) {
                        downloadStatus = .DOWNLOADING
                    } else {
                        alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
                    }
                }
                updater += 1
            }) {
                if let download = modelData.activeDownloads.filter( {$1.isDownloading && $1.book.id == modelData.readingBook?.id} ).first {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else if modelData.readingBook != nil, modelData.readingBook!.inShelf {
                    Image(systemName: "star.slash")
                } else {
                    Image(systemName: "star")
                }
            }.disabled(!modelData.updatingMetadataSucceed)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                guard let book = modelData.readingBook else { return }
                if _viewModel.listVM == nil {
                    _viewModel.listVM = ReadingPositionListViewModel(
                        modelData: modelData, book: book, positions: book.readPos.getDevices()
                    )
                } else {
                    _viewModel.listVM.book = book
                    _viewModel.listVM.positions = book.readPos.getDevices()
                }
                presentingReadPositionList = true
            }) {
                Image(systemName: "book")
            }.disabled(modelData.readingBook?.inShelf == false)
        }
    }
    
    private func deleteToolbarItem() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                alertItem = AlertItem(id: "Delete")
            }) {
                Image(systemName: "trash")
                    .accentColor(.red)
            }.disabled(!modelData.updatingMetadataSucceed)
        }
    }
    
    func deleteBook() {
        guard let book = modelData.readingBook else {
            assert(false, "readingBook is nil")
            return
        }
        guard let endpointUrl = book.library.urlForDeleteBook else {
            return
        }
        let json:[Any] = [[book.id], false]
        
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: []) else { return }
            
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                // self.handleClientError(error)
                defaultLog.warning("error: \(error.localizedDescription)")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                // self.handleServerError(response)
                defaultLog.warning("not httpResponse: \(response.debugDescription)")
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json" {
                DispatchQueue.main.async {
                    handleBookDeleted()
                }
            }
        }
        
        task.resume()
    }
    
    func initStates(book: CalibreBook) {
        shelfName = book.inShelfName.isEmpty ? book.tags.first ?? "Untagged" : book.inShelfName
        shelfNameCustomized = !book.tags.contains(shelfName)
        
        if _viewModel.listVM == nil {
            _viewModel.listVM = ReadingPositionListViewModel(
                modelData: modelData, book: book, positions: book.readPos.getDevices()
            )
        } else {
            _viewModel.listVM.book = book
            _viewModel.listVM.positions = book.readPos.getDevices()
        }
        
        modelData.calibreServerService.getAnnotations(
            book: book,
            formats: book.formats.keys.compactMap { Format(rawValue: $0) }
        )
    }
    
    func previewAction(book: CalibreBook, format: Format, formatInfo: FormatInfo, reader: ReaderType) {
        guard let bookFileUrl = getSavedUrl(book: book, format: format)
        else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return
        }
        
        let readPosition = modelData.getInitialReadingPosition(book: book, format: format, reader: reader)
        
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
        
        presentingReadSheet = true
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

extension BookDetailView : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

@available(macCatalyst 14.0, *)
struct BookDetailView_Previews: PreviewProvider {
    static var modelData = ModelData(mock: true)
     
    static var previews: some View {
        BookDetailView(viewMode: .LIBRARY)
            .environmentObject(modelData)
    }
}
