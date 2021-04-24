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
        
    @State private var downloadStatus = DownloadStatus.INITIAL
    
    var defaultLog = Logger()
    
    struct AlertItem : Identifiable {
        var id: String
    }
    @State private var alertItem: AlertItem?

//    @State private var showingAlert = false
//    @State private var showingRefreshAlert = false
//    @State private var showingDownloadAlert = false
    @State private var selectedFormat = CalibreBook.Format.EPUB
    @State private var selectedPosition = ""
    @State private var updater = 0
    @State private var showingReadSheet = false
    
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
                viewContent(book: book)
                .onAppear() {
                    getMetadata(oldbook: book)
                    // modelData.currentBookId = book.id
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
            if book != nil {
                getMetadata(oldbook: book!)
                if book!.readPos.getDevices().count > 0 {
                    self.selectedPosition = book!.readPos.getDevices()[0].id
                }
            }
        }
        .onChange(of: downloadStatus, perform: { value in
            if downloadStatus == .DOWNLOADED {
                modelData.addToShelf(modelData.readingBook!.id)
            }
        })
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
            if item.id == "Refresh" {
                return Alert(
                    title: Text("Need Refresh"),
                    message: Text("Please Refresh First"),
                    primaryButton: .default(Text("Refresh")
                    ) {
                        getMetadata(oldbook: modelData.readingBook!)
                    },
                    secondaryButton: .cancel()
                )
            }
            if item.id == "Download" {
                return Alert(
                    title: Text("Need Download"),
                    message: Text("Please Download First"),
                    primaryButton: .default(Text("Download"), action: {
                        modelData.downloadFormat(modelData.readingBook!.id, selectedFormat) { result in
                            
                        }
                    }),
                    secondaryButton: .cancel()
                )
            }
            return Alert(title: Text(item.id))
        }.fullScreenCover(isPresented: $showingReadSheet, onDismiss: {showingReadSheet = false} ) {
            EpubReader(bookURL: getSavedUrl(book: modelData.readingBook!))
        }.disabled(modelData.readingBook == nil)
    }
    
    @ViewBuilder
    private func viewContent(book: CalibreBook) -> some View {
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
                Text(ByteCountFormatter.string(fromByteCount: Int64(book.size), countStyle: .file)).font(.subheadline)
                Spacer()
                Text(book.lastModified.description).font(.subheadline)
            }
            HStack {
                Text(book.tagsDescription).font(.subheadline)
                Spacer()
            }
            
            HStack {
                Spacer()
                
                KFImage(book.coverURL)
                    .placeholder {
                        Text("Loading Cover ...")
                    }
                
                Spacer()
//                AsyncImage(
//                    url: book.coverURL) {
//                    Text("Loading ...")
//                }.environmentObject(modelData)
                //.aspectRatio(contentMode: .fit)
            
            }
            
            HStack {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(CalibreBook.Format.allCases) { format in
                        if book.formats[format.rawValue] != nil {
                            Text(format.rawValue).tag(format)
                        }
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onAppear() {
                    if book.formats[modelData.defaultFormat.rawValue] != nil {
                        self.selectedFormat = modelData.defaultFormat
                    } else {
                        CalibreBook.Format.allCases.forEach { format in
                            if book.formats[format.rawValue] != nil {
                                self.selectedFormat = format
                            }
                        }
                    }
                }
                Spacer()
            }
            
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
            .onAppear() {
                if book.readPos.getDevices().count > 0 {
                    self.selectedPosition = book.readPos.getDevices()[0].id
                }
            }
            .onChange(of: selectedPosition) { value in
                modelData.selectedPosition = selectedPosition
            }
            
            Text(book.readPos.getPosition(selectedPosition)?.description ?? UIDevice().name)
            
            #if canImport(GoogleMobileAds)
            Banner()
            #endif
            
            WebViewUI(content: book.comments, baseURL: book.commentBaseURL)
                .frame(height: CGFloat(400), alignment: .center)
            
//            commentWebView
//                .frame(height: CGFloat(400), alignment: .center)
//                .onAppear {
//                    commentWebView.setContent(book.comments, URL(string: book.library.server.baseUrl))
//                }
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
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                modelData.goToPreviousBook()
            }) {
                Image(systemName: "chevron.up")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {
                modelData.goToNextBook()
            }) {
                Image(systemName: "chevron.down")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(action: {showingReadSheet = true}) {
                Image(systemName: "book")
            }
        }
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                guard let book = modelData.readingBook else {
                    assert(false, "modelData.readingBook is nil")
                    return
                }
                if book.inShelf {
                    modelData.clearCache(inShelfId: book.inShelfId, selectedFormat)
                    modelData.removeFromShelf(inShelfId: book.inShelfId)
                    downloadStatus = .INITIAL
                } else if downloadStatus == .INITIAL {
                    let downloading = modelData.downloadFormat(book.id, selectedFormat) { isSuccess in
                        if isSuccess {
                            downloadStatus = .DOWNLOADED
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
            }
        }
    }

    func getMetadata(oldbook: CalibreBook) {
        let endpointUrl = URL(string: oldbook.library.server.baseUrl + "/cdb/cmd/list/0?library_id=" + oldbook.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        let json:[Any] = [["all"], "", "", "id:\(oldbook.id)", -1]
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
                    //book.comments = error.localizedDescription
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    // self.handleServerError(response)
                    defaultLog.warning("not httpResponse: \(response.debugDescription)")
                    //book.comments = response.debugDescription
                    return
                }
                
                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                   let data = data,
                   let string = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        //self.webView.loadHTMLString(string, baseURL: url)
                        //                            defaultLog.warning("httpResponse: \(string)")
                        //book.comments = string
                        guard var book = handleLibraryBooks(oldbook: oldbook, json: data) else {
                            return
                        }
                        
                        if( book.readPos.getDevices().isEmpty) {
                            book.readPos.addInitialPosition(UIDevice().name, "FolioReader")
                        }
                        
                        modelData.updateBook(book: book)
                        
//                        commentWebView.setContent(book.comments, URL(string: book.library.server.baseUrl))
                        
                        if( book.formats[selectedFormat.rawValue] == nil ) {
                            CalibreBook.Format.allCases.forEach { format in
                                if book.formats[format.rawValue] != nil {
                                    selectedFormat = format
                                }
                            }
                        }
                        
                        if( book.readPos.getPosition(selectedPosition) == nil ) {
                            if !book.readPos.getDevices().isEmpty {
                                selectedPosition = book.readPos.getDevices()[0].id
                            }
                        }
                        
                        modelData.readingBookReloadCover.send()
                    }
                }
            }
            
            task.resume()
            
        }catch{
        }
    }
    
    enum LibraryError: Error {
        case runtimeError(String)
    }
    
    func handleLibraryBooks(oldbook: CalibreBook, json: Data) -> CalibreBook? {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary,
              let resultElement = root["result"] as? NSDictionary,
              let bookIds = resultElement["book_ids"] as? NSArray,
              let dataElement = resultElement["data"] as? NSDictionary,
              let bookId = bookIds.firstObject as? NSNumber else {
            self.alertItem = AlertItem(id: "Failed to Parse Calibre Server Response.")
            return nil
        }
        
        let bookIdKey = bookId.stringValue
        var book = oldbook
        if let d = dataElement["title"] as? NSDictionary, let v = d[bookIdKey] as? String {
            book.title = v
        }
        if let d = dataElement["publisher"] as? NSDictionary, let v = d[bookIdKey] as? String {
            book.publisher = v
        }
        if let d = dataElement["series"] as? NSDictionary, let v = d[bookIdKey] as? String {
            book.series = v
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime
        if let d = dataElement["pubdate"] as? NSDictionary, let v = d[bookIdKey] as? NSDictionary, let t = v["v"] as? String, let date = dateFormatter.date(from: t) {
            book.pubDate = date
        }
        if let d = dataElement["last_modified"] as? NSDictionary, let v = d[bookIdKey] as? NSDictionary, let t = v["v"] as? String, let date = dateFormatter.date(from: t) {
            book.lastModified = date
        }
        if let d = dataElement["timestamp"] as? NSDictionary, let v = d[bookIdKey] as? NSDictionary, let t = v["v"] as? String, let date = dateFormatter.date(from: t) {
            book.timestamp = date
        }
        
        if let d = dataElement["tags"] as? NSDictionary, let v = d[bookIdKey] as? NSArray {
            book.tags = v.compactMap { (t) -> String? in
                t as? String
            }
        }
        if let d = dataElement["size"] as? NSDictionary, let v = d[bookIdKey] as? NSNumber {
            book.size = v.intValue
        }
        
        if let d = dataElement["authors"] as? NSDictionary, let v = d[bookIdKey] as? NSArray {
            book.authors = v.compactMap { (t) -> String? in
                if let t = t as? String {
                    return t
                } else {
                    return nil
                }
            }
        }
//        authors.forEach { (key, value) in
//            let authors = value as! NSArray
//            book.authors = authors[0] as! String
//            //                bookAuthors = book.authors
//        }
        
        let comments = dataElement["comments"] as! NSDictionary
        comments.forEach { (key, value) in
            book.comments = value as? String ?? "Without Comments"
        }
        
        do {
            if( dataElement["#read_pos"] == nil ) {
                throw LibraryError.runtimeError("need #read_pos custom column")
            }
            let readPosElement = dataElement["#read_pos"] as! NSDictionary
            try readPosElement.forEach { (key, value) in
                if( value is NSString ) {
                    let readPosString = value as! NSString
                    let readPosObject = try JSONSerialization.jsonObject(with: Data(base64Encoded: readPosString as String)!, options: [])
                    let readPosDict = readPosObject as! NSDictionary
                    defaultLog.info("readPosDict \(readPosDict)")
                    
                    let deviceMapObject = readPosDict["deviceMap"]
                    let deviceMapDict = deviceMapObject as! NSDictionary
                    deviceMapDict.forEach { key, value in
                        let deviceName = key as! String
                        let deviceReadingPositionDict = value as! [String: Any]
                        //TODO merge
                        
                        var deviceReadingPosition = book.readPos.getPosition(deviceName)
                        if( deviceReadingPosition == nil ) {
                            deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: "FolioReader")
                        }
                        
                        deviceReadingPosition!.readerName = deviceReadingPositionDict["readerName"] as! String
                        deviceReadingPosition!.lastReadPage = deviceReadingPositionDict["lastReadPage"] as! Int
                        deviceReadingPosition!.lastReadChapter = deviceReadingPositionDict["lastReadChapter"] as! String
                        deviceReadingPosition!.furthestReadPage = deviceReadingPositionDict["furthestReadPage"] as! Int
                        deviceReadingPosition!.furthestReadChapter = deviceReadingPositionDict["furthestReadChapter"] as! String
                        deviceReadingPosition!.maxPage = deviceReadingPositionDict["maxPage"] as! Int
                        if let lastPosition = deviceReadingPositionDict["lastPosition"] {
                            deviceReadingPosition!.lastPosition = lastPosition as! [Int]
                        }
                        
                        book.readPos.updatePosition(deviceName, deviceReadingPosition!)
                        defaultLog.info("book.readPos.getDevices().count \(book.readPos.getDevices().count)")
                    }
                }
            }
        } catch {
            defaultLog.warning("handleLibraryBooks: \(error.localizedDescription)")
        }
        return book
    }
    
    
    func getSavedUrl(book: CalibreBook) -> URL {
        var downloadBaseURL = try!
            FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
        var savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(selectedFormat.rawValue.lowercased())")
        if FileManager.default.fileExists(atPath: savedURL.path) {
            return savedURL
        }
        
        downloadBaseURL = try!
            FileManager.default.url(for: .cachesDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
        savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(selectedFormat.rawValue.lowercased())")
        if FileManager.default.fileExists(atPath: savedURL.path) {
            return savedURL
        }
        
        return savedURL
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
    
    func handleBookDeleted() {
//        modelData.libraryInfo.deleteBook(book: book)
        //TODO
        //getMetadata()
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
