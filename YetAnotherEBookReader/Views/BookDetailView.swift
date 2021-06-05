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
import KingfisherSwiftUI

enum DownloadStatus: String, CaseIterable, Identifiable {
    case INITIAL
    case DOWNLOADING
    case DOWNLOADED
    
    var id: String { self.rawValue }
}

@available(macCatalyst 14.0, *)
struct BookDetailView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.openURL) var openURL
        
    @State private var downloadStatus = DownloadStatus.INITIAL
    
    var defaultLog = Logger()
    
    struct AlertItem : Identifiable {
        var id: String
        var msg: String?
    }
    @State private var alertItem: AlertItem?

//    @State private var presentingUpdateAlert = false
//    @State private var showingRefreshAlert = false
//    @State private var showingDownloadAlert = false
    
    @State private var selectedFormatShowDetail = false
    @State private var selectedFormat = CalibreBook.Format.EPUB
    @State private var selectedFormatSize:UInt64 = 0
    @State private var selectedFormatMTime = Date()
    @State private var selectedFormatCached = false
    @State private var selectedFormatCachedSize:UInt64 = 0
    @State private var selectedFormatCachedMTime = Date()
    @State private var selectedFormatTOC = "Uninitialized"
    @State private var selectedFormatReader = ReaderType.UNSUPPORTED
    @State private var selectedFormatReaderShowDetail = false
    
    @State private var selectedPositionShowDetail = false
    @State private var selectedPosition = ""
    @State private var updater = 0
    @State private var showingReadSheet = false
    
    @State private var shelfNameShowDetail = false
    @State private var shelfName = ""
    @State private var shelfNameCustomized = false
    // var commentWebView = WebViewUI()
    
    // let rvc = ReaderViewController()
    // var pdfView = PDFViewUI()
    
    class DownloadDelegate : NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            //TODO
        }
        
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            //TODO
        }
        
    }
    
    var body: some View {
        ScrollView {
            if let book = modelData.readingBook {
                viewContent(book: book, isCompat: sizeClass == .compact)
                .onAppear() {
                    resetStates()
                    modelData.getMetadataNew(oldbook: book, completion: initStates(book:))
                }
                .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                .navigationTitle(Text(modelData.readingBook!.title))
            } else {
                EmptyView()
            }
        }
        
        .toolbar {
            toolbarContent()
        }
        .onChange(of: modelData.readingBook) {book in
            if let book = book {
                resetStates()
                modelData.getMetadataNew(oldbook: book, completion: initStates(book:))
            }
        }
        .onChange(of: downloadStatus) { value in
            if downloadStatus == .DOWNLOADED {
                modelData.addToShelf(modelData.readingBook!.id, shelfName: shelfName)
            }
        }
        .onChange(of: selectedFormat) { newFormat in
            if newFormat == CalibreBook.Format.UNKNOWN {
                return
            }
            print("selectedFormat \(selectedFormat.rawValue)")
            if let book = modelData.readingBook {
                if let fValStr = book.formats[newFormat.rawValue],
                   let fValData = Data(base64Encoded: fValStr),
                   let fVal = try? JSONSerialization.jsonObject(with: fValData, options: []) as? NSDictionary {
                    if let sizeVal = fVal["size"] as? NSNumber {
                        self.selectedFormatSize = sizeVal.uint64Value
                    }
                    if let mtimeVal = fVal["mtime"] as? String {
                        let dateFormatter = ISO8601DateFormatter()
                        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
                        if let mtime = dateFormatter.date(from: mtimeVal) {
                            self.selectedFormatMTime = mtime
                        }
                    }
                }
                initCacheStates(book: book, format: newFormat)
                
                modelData.getBookManifest(book: book, format: newFormat) { manifest in
                    parseManifestToTOC(json: manifest)
                }
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
            if item.id == "Download" {
                return Alert(
                    title: Text("Need Download"),
                    message: Text("Please Download First"),
                    primaryButton: .default(Text("Download"), action: {
                        modelData.downloadFormat(book: modelData.readingBook!, format: selectedFormat, modificationDate: selectedFormatMTime) { result in
                            
                        }
                    }),
                    secondaryButton: .cancel()
                )
            }
            if item.id == "Updating" {
                let alert = Alert(title: Text("Updating"), message: Text("Update Book Metadata..."), dismissButton: .cancel() {
                    if modelData.updatingMetadata && modelData.updatingMetadataTask != nil {
                        modelData.updatingMetadataTask!.cancel()
                    }
                })
                return alert
            }
            if item.id == "Updated" {
                return Alert(title: Text("Updated"), message: Text(item.msg ?? "Success"))
            }
            if item.id == "ForwardProgress" {
                return Alert(title: Text("Confirm Forward Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    modelData.updateCurrentPosition()
                }), secondaryButton: .cancel())
            }
            if item.id == "BackwardProgress" {
                return Alert(title: Text("Confirm Backwards Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    modelData.updateCurrentPosition()
                }), secondaryButton: .cancel())
            }
            if item.id == "ReadingPosition" {
                return Alert(title: Text("Confirm Reading Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    let selectedPosition = modelData.getSelectedReadingPosition()
                    readBook(position: selectedPosition!)
                }), secondaryButton: .cancel())
            }
            return Alert(title: Text(item.id))
        }
        .fullScreenCover(isPresented: $showingReadSheet, onDismiss: {showingReadSheet = false} ) {
            if let book = modelData.readingBook,
               let bookFileUrl = getSavedUrl(book: book, format: selectedFormat) {
                YabrEBookReader(
                    bookURL: bookFileUrl,
                    bookFormat: selectedFormat,
                    bookReader: selectedFormatReader
                )
            } else {
                Text("Nil Book")
            }
        }

        .disabled(modelData.readingBook == nil)
    }
    
    @ViewBuilder
    private func viewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(book.authorsDescription).font(.subheadline)
                Spacer()
                Text(book.publisher).font(.subheadline)
            }
            HStack {
                Text(book.series).font(.subheadline)
                Spacer()
                Text(book.pubDate.description).font(.subheadline)
            }
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: Int64(selectedFormatSize), countStyle: .file)).font(.subheadline)
                Spacer()
                
                    
                Text(modelData.updatingMetadataStatus)
                if modelData.updatingMetadata {
                    Button(action: {
                        //TODO cancel
                    }) {
                        Image(systemName: "xmark")
                    }
                } else {
                    Button(action: {
                        if let book = modelData.readingBook {
                            modelData.kfImageCache.removeImage(forKey: book.coverURL.absoluteString)
                            resetStates()
                            modelData.getMetadataNew(oldbook: book) { newbook in
                                initStates(book: newbook)
                                modelData.getBookManifest(book: newbook, format: selectedFormat) { manifest in
                                    self.parseManifestToTOC(json: manifest)
                                }
                            }
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                Text(book.lastModified.description).font(.subheadline)
                
            }
            HStack {
                Text(book.tagsDescription).font(.subheadline)
                Spacer()
                if let id = book.identifiers["goodreads"] {
                    Button(action:{
                        openURL(URL(string: "https://www.goodreads.com/book/show/\(id)")!)
                    }) {
                        Image("icon-goodreads").resizable().frame(width: 24, height: 24, alignment: .center)
                    }
                } else {
                    Button(action:{
                        openURL(URL(string: "https://www.goodreads.com/")!)
                    }) {
                        Image("icon-goodreads").resizable().frame(width: 24, height: 24, alignment: .center)
                    }.hidden()
                }
                if let id = book.identifiers["amazon"] {
                    Button(action:{
                        openURL(URL(string: "http://www.amazon.com/dp/\(id)")!)
                    }) {
                        Image("icon-amazon").resizable().frame(width: 24, height: 24, alignment: .center)
                    }
                } else {
                    Button(action:{
                        openURL(URL(string: "https://www.amazon.com/")!)
                    }) {
                        Image("icon-amazon").resizable().frame(width: 24, height: 24, alignment: .center)
                    }.hidden()
                }
            }
            
            #if canImport(GoogleMobileAds)
            Banner()
            #endif
            
            if isCompat {
                VStack(alignment: .center, spacing: 4) {
                    Spacer()
                    
                    KFImage(book.coverURL)
                        .placeholder {
                            Text("Loading Cover ...")
                        }
                    
                    ScrollView {
                        Text(selectedFormatTOC)
                    }
                    .frame(height: 400, alignment: .center)
                    
                    Spacer()
                }
            } else {
                HStack {
                    Spacer()
                    
                    KFImage(book.coverURL)
                        .placeholder {
                            Text("Loading Cover ...")
                        }
                    
                    ScrollView {
                        Text(selectedFormatTOC)
                    }
                    .frame(height: 400, alignment: .center)
                    
                    Spacer()
                }
            }
            
            
            #if canImport(GoogleMobileAds)
            Banner()
            #endif
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shelf")
                    
                    if shelfNameCustomized {
                        TextField("Shelf Name", text: $shelfName)
                    } else {
                        Picker(shelfName, selection: $shelfName) {
                            ForEach(book.tags, id:\.self) {
                                Text($0).tag($0)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    Button(action: { shelfNameShowDetail.toggle() } ) {
                        if shelfNameShowDetail {
                            Image(systemName: "chevron.up")
                        } else {
                            Image(systemName: "chevron.down")
                        }
                    }
                }.onChange(of: shelfName) { value in
                    modelData.readingBook!.inShelfName = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    modelData.updateBook(book: modelData.readingBook!)
                }
                if shelfNameShowDetail {
                    Toggle("Customize Shelf Name", isOn: $shelfNameCustomized)
                }
            
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Format")
                        
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(CalibreBook.Format.allCases) { format in
                                if book.formats[format.rawValue] != nil {
                                    Text(format.rawValue).tag(format)
                                }
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        Button(action:{ selectedFormatShowDetail.toggle() }) {
                            if selectedFormatShowDetail {
                                Image(systemName: "chevron.up")
                            } else {
                                Image(systemName: "chevron.down")
                            }
                        }
                    }
                    
                    if selectedFormatShowDetail {
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(selectedFormatSize), countStyle: .file)).font(.subheadline)
                            Spacer()
                            if selectedFormatCached {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(selectedFormatCachedSize), countStyle: .file)).font(.subheadline)
                            }
                        }
                        HStack {
                            Text(selectedFormatMTime.description)
                            Spacer()
                            if selectedFormatCached {
                                Text(selectedFormatCachedMTime.description)
                            }
                        }
                        HStack {
                            Spacer()
                            #if DEBUG
                            Button(action: {
                                // move from cache to downloaded
                                do {
                                    let cacheDir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                                    let oldURL = cacheDir.appendingPathComponent("\(book.library.name) - \(book.id).\(selectedFormat.rawValue.lowercased())", isDirectory: false)
                                    if FileManager.default.fileExists(atPath: oldURL.path), let newURL = getSavedUrl(book: book, format: selectedFormat) {
                                        try FileManager.default.moveItem(at: oldURL, to: newURL)
                                        initCacheStates(book: book, format: selectedFormat)
                                    }
                                } catch {
                                    print(error)
                                }
                            }) {
                                Image(systemName: "wrench.and.screwdriver")
                            }
                            #endif
                            Button(action:{
                                if let book = modelData.readingBook {
                                    modelData.clearCache(book: book, format: selectedFormat)
                                    modelData.downloadFormat(book: book, format: selectedFormat, modificationDate: selectedFormatMTime) { success in
                                        initCacheStates(book: book, format: selectedFormat)
                                    }
                                }
                            }) {
                                Image(systemName: "tray.and.arrow.down")
                            }
                            Button(action:{
                                if let book = modelData.readingBook {
                                    modelData.clearCache(book: book, format: selectedFormat)
                                    initCacheStates(book: book, format: selectedFormat)
                                }
                            }) {
                                Image(systemName: "tray.and.arrow.up")
                            }.disabled(!selectedFormatCached)
                        }
                    }
                    
                    
                    HStack {
                        Text("Read At")
                        Picker("Position", selection: $selectedPosition) {
                            ForEach(book.readPos.getDevices(), id: \.self) { position in
                                HStack {
                                    Text(position.id)
                                        .font(.body)
                                        .padding()
                                }.tag(position.id)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                        .onChange(of: selectedPosition) { value in
                            modelData.selectedPosition = selectedPosition
                            guard let readers = modelData.formatReaderMap[selectedFormat] else { return }
                            selectedFormatReader = readers.reduce(into: readers.first!) {
                                if $1.rawValue == book.readPos.getPosition(self.selectedPosition)?.readerName {
                                    $0 = $1
                                }
                            }
                        }
                        .onChange(of: modelData.updatedReadingPosition) { value in
                            if let selectedPosition = modelData.getSelectedReadingPosition() {
                                if modelData.updatedReadingPosition.isSameProgress(with: selectedPosition) {
                                    return
                                }
                                if modelData.updatedReadingPosition < selectedPosition {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        alertItem = AlertItem(id: "BackwardProgress", msg: "Previous \(selectedPosition.description) VS Current \(modelData.updatedReadingPosition.description)")
                                    }
                                } else if selectedPosition << modelData.updatedReadingPosition {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        alertItem = AlertItem(id: "ForwardProgress", msg: "Previous \(selectedPosition.description) VS Current \(modelData.updatedReadingPosition.description)")
                                    }
                                }
                                else {
                                    modelData.updateCurrentPosition()
                                }
                            }
                        }
                        Button(action:{ selectedPositionShowDetail.toggle() }) {
                            if selectedPositionShowDetail {
                                Image(systemName: "chevron.up")
                            } else {
                                Image(systemName: "chevron.down")
                            }
                        }
                    }
                    
                    if selectedPositionShowDetail {
                        Text(modelData.getSelectedReadingPosition()?.description ?? modelData.getDeviceReadingPosition()?.description ?? modelData.deviceName)
                            .frame(height: 120)
                    }
                    
                    HStack {
                        Text("Reader")
                        
                        Picker("Reader", selection: $selectedFormatReader) {
                            ForEach(ReaderType.allCases) { type in
                                if let types = modelData.formatReaderMap[selectedFormat],
                                   types.contains(type) {
                                    Text(type.rawValue).tag(type)
                                }
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        Button(action:{ selectedFormatReaderShowDetail.toggle() }) {
                            if selectedFormatReaderShowDetail {
                                Image(systemName: "chevron.up")
                            } else {
                                Image(systemName: "chevron.down")
                            }
                        }.hidden()
                    }
                    
                }
            
                WebViewUI(content: book.comments, baseURL: book.commentBaseURL)
                    .frame(height: CGFloat(400), alignment: .center)
            }

        }   //VStack
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                alertItem = AlertItem(id: "Delete")
            }) {
                Image(systemName: "trash")
                    .accentColor(.red)
            }.disabled(!modelData.updatingMetadataSucceed)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                modelData.goToPreviousBook()
            }) {
                Image(systemName: "chevron.up")
            }.disabled(!modelData.updatingMetadataSucceed)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                modelData.goToNextBook()
            }) {
                Image(systemName: "chevron.down")
            }.disabled(!modelData.updatingMetadataSucceed)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                guard let book = modelData.readingBook else {
                    assert(false, "modelData.readingBook is nil")
                    return
                }
                if book.inShelf {
                    modelData.clearCache(inShelfId: book.inShelfId, selectedFormat)
                    modelData.removeFromShelf(inShelfId: book.inShelfId)
                    downloadStatus = .INITIAL
                    initCacheStates(book: book, format: selectedFormat)
                } else if downloadStatus == .INITIAL {
                    let downloading = modelData.downloadFormat(book: book, format: selectedFormat, modificationDate: selectedFormatMTime) { isSuccess in
                        if isSuccess {
                            downloadStatus = .DOWNLOADED
                            initCacheStates(book: book, format: selectedFormat)
                        } else {
                            downloadStatus = .INITIAL
                            alertItem = AlertItem(id: "DownloadFailure")
                        }
                    }
                    if downloading {
                        downloadStatus = .DOWNLOADING
                    }
                }
                updater += 1
            }) {
                if downloadStatus == .DOWNLOADING {
                    Text("Downloading")
                } else if modelData.readingBook != nil, modelData.readingBook!.inShelf {
                    Image(systemName: "star.slash")
                } else {
                    Image(systemName: "star")
                }
            }.disabled(!modelData.updatingMetadataSucceed)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                let devicePosition = modelData.getDeviceReadingPosition()
                let selectedPosition = modelData.getSelectedReadingPosition()
                
                if devicePosition == nil && selectedPosition == nil {
                    readBook(position: BookDeviceReadingPosition(id: modelData.deviceName, readerName: ""))
                    return
                }
                if devicePosition == nil && selectedPosition != nil {
                    readBook(position: selectedPosition!)
                    return
                }
                if devicePosition != nil && selectedPosition == nil {
                    readBook(position: devicePosition!)
                    return
                }
                if devicePosition! == selectedPosition! {
                    readBook(position: devicePosition!)
                    return
                } else {
                    alertItem = AlertItem(id: "ReadingPosition", msg: "You have picked a different reading position than that of this device, please confirm.\n\(devicePosition!.description) VS \(selectedPosition!.description)")
                }
            }) {
                Image(systemName: "book")
            }.disabled(modelData.readingBook?.inShelf == false)
        }
    }
    
    func deleteBook() {
        guard let book = modelData.readingBook else {
            assert(false, "readingBook is nil")
            return
        }
        let endpointUrl = URL(string: book.library.server.baseUrl + "/cdb/cmd/remove/0?library_id=" + book.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        let json:[Any] = [[book.id], false]
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            
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
            
        }catch{
        }
    }
    
    func resetStates() {
        selectedFormat = CalibreBook.Format.UNKNOWN
        selectedPosition = ""
        selectedFormatReader = ReaderType.UNSUPPORTED
    }
    
    func initStates(book: CalibreBook) {
        CalibreBook.Format.allCases.forEach { format in
            if book.formats[format.rawValue] != nil && modelData.getCacheInfo(book: book, format: format) != nil {
                self.selectedFormat = format
            }
        }
        
        if self.selectedFormat == CalibreBook.Format.UNKNOWN, book.formats[modelData.defaultFormat.rawValue] != nil {
            self.selectedFormat = modelData.defaultFormat
        }
        
        if self.selectedFormat == CalibreBook.Format.UNKNOWN {
            CalibreBook.Format.allCases.forEach { format in
                if book.formats[format.rawValue] != nil {
                    self.selectedFormat = format
                }
            }
        }
        
        if let position = modelData.getDeviceReadingPosition() {
            self.selectedPosition = position.id
        } else if let position = modelData.getLatestReadingPosition() {
            self.selectedPosition = position.id
        } else {
            self.selectedPosition = modelData.getInitialReadingPosition().id
        }
        
        shelfName = book.inShelfName.isEmpty ? book.tags.first ?? "Untagged" : book.inShelfName
        shelfNameCustomized = !book.tags.contains(shelfName)
    }
    
    func initCacheStates(book: CalibreBook, format: CalibreBook.Format) {
        if let cacheInfo = modelData.getCacheInfo(book: book, format: format), (cacheInfo.1 != nil) {
            print("cacheInfo: \(cacheInfo.0) \(cacheInfo.1!) vs \(self.selectedFormatSize) \(self.selectedFormatMTime)")
            selectedFormatCached = true
            selectedFormatCachedSize = cacheInfo.0
            selectedFormatCachedMTime = cacheInfo.1!
        } else {
            selectedFormatCached = false
        }
    }
    
    func readBook(position: BookDeviceReadingPosition) {
        modelData.updatedReadingPosition.update(with: position)
        showingReadSheet = true
    }
    
    func handleBookDeleted() {
//        modelData.libraryInfo.deleteBook(book: book)
        //TODO
        //getMetadata()
    }
    
    func parseManifestToTOC(json: Data) {
        selectedFormatTOC = "Without TOC"
        
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            #if DEBUG
            selectedFormatTOC = String(data: json, encoding: .utf8) ?? "String Decoding Failure"
            #endif
            return
        }
        
        guard let tocNode = root["toc"] as? NSDictionary else {
            #if DEBUG
            selectedFormatTOC = String(data: json, encoding: .utf8) ?? "String Decoding Failure"
            #endif
            
            if let jobStatus = root["job_status"] as? String, jobStatus == "waiting" || jobStatus == "running" {
                selectedFormatTOC = "Generating TOC, Please try again later"
            }
            return
        }
        
        guard let childrenNode = tocNode["children"] as? NSArray else {
            return
        }
        
        let tocString = childrenNode.reduce(into: String()) { result, childNode in
            result = result + ((childNode as! NSDictionary)["title"] as! String) + "\n"
        }
        
        selectedFormatTOC = tocString
    }
}

@available(macCatalyst 14.0, *)
struct BookDetailView_Previews: PreviewProvider {
    static var modelData = ModelData()
    @State static var book = CalibreBook(id: 1, library: CalibreLibrary(server: CalibreServer(baseUrl: "", username: "", password: ""), key: "Local", name: "Local"), title: "Title", authors: ["Author"], comments: "", rating: 0, formats: ["EPUB":""], readPos: BookReadingPosition(), inShelf: true)
    static var previews: some View {
        BookDetailView()
            .environmentObject(modelData)
    }
}
