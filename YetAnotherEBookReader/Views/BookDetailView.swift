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
    
    @Binding var book: CalibreBook
    
    @State private var readingPositions = [String]()
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
    
    var commentWebView = WebViewUI()
    
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
            VStack(alignment: .leading) {
                HStack {
                    Text(book.authors).font(.subheadline)
                    Spacer()
                }
                
                AsyncImage(
                    url: book.coverURL) {
                    Text("Loading ...")
                }.aspectRatio(contentMode: .fit)
                
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
                        if self.book.formats[modelData.defaultFormat.rawValue] != nil {
                            self.selectedFormat = modelData.defaultFormat
                        } else {
                            CalibreBook.Format.allCases.forEach { format in
                                if self.book.formats[format.rawValue] != nil {
                                    self.selectedFormat = format
                                }
                            }
                        }
                    }
                    Spacer()
                }
                
                Picker("Position", selection: $selectedPosition) {
                    ForEach(self.book.readPos.getDevices(), id: \.self) { position in
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
                    if self.book.readPos.getDevices().count > 0 {
                        self.selectedPosition = self.book.readPos.getDevices()[0].id
                    }
                }
                .onChange(of: book) {_ in
                    getMetadata()
                    if self.book.readPos.getDevices().count > 0 {
                        self.selectedPosition = self.book.readPos.getDevices()[0].id
                    }
                }
                
                Text(self.book.readPos.getPosition(selectedPosition)?.description ?? UIDevice().name)
                
//                HStack {
//                    Spacer()
//                    Button(action: {getMetadata()}) {
//                        Text("Refresh")
//                    }
//                    Spacer()
//                    Button(action: {downloadFormat(book: book, format: selectedFormat)}) {
//                        Text("Download")
//                    }
//                    Spacer()
//                    Button(action: {clearCache(book: book, format: selectedFormat)}) {
//                        Text("Clear")
//                    }
//                    Spacer()
//                }
//                .padding(EdgeInsets(top: 5, leading: 10, bottom: 10, trailing: 5))
                
                Banner()
                
                VStack {
                    // rvc.frame(width: CGFloat(100), height: CGFloat(1), alignment: .center)
                    // pdfView.frame(width: CGFloat(100), height: CGFloat(1), alignment: .center)
                    
                    commentWebView
                        .frame(height: CGFloat(400), alignment: .center)
                        .onAppear {
                            commentWebView.setContent(self.book.comments, URL(string: self.book.library.server.baseUrl))
                        }
                }
            }   //VStack
            .onAppear() {
                getMetadata()
                modelData.currentBookId = book.id
            }
            
        }
        .padding(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
        .navigationTitle(Text(book.title))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    alertItem = AlertItem(id: "Delete")
                }) {
                    Image(systemName: "trash")
                        .accentColor(.red)
                }
            }
//            ToolbarItem(placement: .confirmationAction) {
//                Button(action: {readFormat()}) {
//                    Text("Read")
//                }
//            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    if let curIndex = modelData.filteredBookList.firstIndex(of: book.id), curIndex > 0 {
                        modelData.currentBookId = modelData.filteredBookList[curIndex-1]
                        
                    }
                }) {
                    Image(systemName: "chevron.up")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {}) {
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
                    } else if book.inShelf {
                        Image(systemName: "star.slash")
                    } else {
                        Image(systemName: "star")
                    }
                }
            }
        }
        .onChange(of: downloadStatus, perform: { value in
            if downloadStatus == .DOWNLOADED {
                modelData.addToShelf(book.id)
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
                        getMetadata()
                    },
                    secondaryButton: .cancel()
                )
            }
            if item.id == "Download" {
                return Alert(
                    title: Text("Need Download"),
                    message: Text("Please Download First"),
                    primaryButton: .default(Text("Download"), action: {
                        modelData.downloadFormat(book.id, selectedFormat) { result in
                            
                        }
                    }),
                    secondaryButton: .cancel()
                )
            }
            return Alert(title: Text(item.id))
        }.fullScreenCover(isPresented: $showingReadSheet, onDismiss: {showingReadSheet = false} ) {
            EpubReader(bookURL: getSavedUrl(), bookDetailView: self)
        }
    }

    func getMetadata() {
        let endpointUrl = URL(string: book.library.server.baseUrl + "/cdb/cmd/list/0?library_id=" + book.library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        let json:[Any] = [["all"], "", "", "id:\(book.id)", -1]
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
                        handleLibraryBooks(json: data)
                        
                        if( book.readPos.getDevices().isEmpty) {
                            book.readPos.addInitialPosition(UIDevice().name, "FolioReader")
                        }
                        
                        commentWebView.setContent(book.comments, URL(string: book.library.server.baseUrl))
                        
                        readingPositions.removeAll()
                        book.readPos.getDevices().forEach { position in
                            readingPositions.append("\(position.id) with \(position.readerName): \(position.lastPosition[0]) \(position.lastPosition[1]) \(position.lastPosition[2]) \(position.lastReadPage)")
                        }
                        
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
                        
                        //                            if( book.readPos.deviceMap.isEmpty ) {
                        //                                progress = "Progress: Not Started"
                        //                            } else {
                        //                                progress = "Reading on"
                        //                            }
                        //                            defaultLog.info("readingPositions: \(readingPositions.count)")
                        //                            defaultLog.info("book.readPos.getDevices: \(book.readPos.getDevices())")
                        
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
    
    func handleLibraryBooks(json: Data) {
        do {
            let root = try JSONSerialization.jsonObject(with: json, options: []) as! NSDictionary
            let resultElement = root["result"] as! NSDictionary
            let bookIds = resultElement["book_ids"] as! NSArray
            let dataElement = resultElement["data"] as! NSDictionary
            
            let titles = dataElement["title"] as! NSDictionary
            titles.forEach { (key, value) in
                book.title = value as! String
            }
            
            let authors = dataElement["authors"] as! NSDictionary
            authors.forEach { (key, value) in
                let authors = value as! NSArray
                book.authors = authors[0] as! String
                //                bookAuthors = book.authors
            }
            
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
            
        } catch {
            defaultLog.warning("handleLibraryBooks: \(error.localizedDescription)")
        }
    }
    
    
    func getSavedUrl() -> URL {
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
    
    //func readFormat(book: Book, format: Book.Format) {
    func readFormat() {
//        if(book.readPos.isEmpty) {
//            self.showingRefreshAlert = true
//            self.showingAlert = true
//            return
//        }
        
        do {
            let downloadBaseURL = try
                FileManager.default.url(for: .cachesDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil,
                                        create: false)
            let savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(selectedFormat.rawValue.lowercased())")
            defaultLog.info("downloadBaseURL: \(downloadBaseURL.absoluteString)")
            defaultLog.info("savedURL: \(savedURL.absoluteString)")
            
            if( !selectedPosition.isEmpty ) {
                if var position = book.readPos.getPosition(selectedPosition) {
                    let curName = UIDevice().name
                    if position.id != curName {
                        position.id = curName
                        book.readPos.updatePosition(curName, position)
                    }
                }
            }
            
            // modelData.isReading = true;
//            if(selectedFormat == Book.Format.EPUB) {
//                rvc.openBook(savedURL, self)
//            }
//            if( selectedFormat == Book.Format.PDF) {
//                pdfView.open(pdfURL: savedURL, bookDetailView: self)
//            }
        } catch {
            
        }
        
    }
    
    func updateCurrentPosition(_ position: [String: Any]?) {
        guard (position != nil) else { return }
        
        do {
            
            let deviceName = UIDevice().name
            
            var deviceReadingPosition = book.readPos.getPosition(deviceName)
            if( deviceReadingPosition == nil ) {
                deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: "FolioReader")
            }
            
            defaultLog.info("pageNumber:  \(position!["pageNumber"]! as! Int)")
            defaultLog.info("pageOffsetX: \(position!["pageOffsetX"]! as! CGFloat)")
            defaultLog.info("pageOffsetY: \(position!["pageOffsetY"]! as! CGFloat)")
            
            deviceReadingPosition!.lastPosition[0] = position!["pageNumber"]! as! Int
            deviceReadingPosition!.lastPosition[1] = Int((position!["pageOffsetX"]! as! CGFloat).rounded())
            deviceReadingPosition!.lastPosition[2] = Int((position!["pageOffsetY"]! as! CGFloat).rounded())
            deviceReadingPosition!.lastReadPage = position!["pageNumber"]! as! Int
            
            book.readPos.updatePosition(deviceName, deviceReadingPosition!)
            
            var deviceMapSerialize = [String: Any]()
            try book.readPos.getCopy().forEach { key, value in
                deviceMapSerialize[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            }
            
            
            let readPosData = try JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []).base64EncodedString()
            
            let endpointUrl = URL(string: book.library.server.baseUrl + "/cdb/cmd/set_metadata/0?library_id=" + book.library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
            let json:[Any] = ["fields", book.id, [["#read_pos", readPosData]]]
            
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            defaultLog.warning("JSON: \(String(data: data, encoding: .utf8)!)")
            
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
                
                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                   let data = data,
                   let string = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        //self.webView.loadHTMLString(string, baseURL: url)
                        //result = string
                        //                            defaultLog.warning("httpResponse: \(string)")
                    }
                }
            }
            
            task.resume()
            
            self.updater += 1
            
        }catch{
        }
        
        // modelData.isReading = false
    }
    
    func getSelectedReadingPosition() -> BookDeviceReadingPosition? {
        return book.readPos.getPosition(selectedPosition)
    }
    
    
    func deleteBook() {
        let endpointUrl = URL(string: book.library.server.baseUrl + "/cdb/cmd/remove/0?library_id=" + book.library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
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
        getMetadata()
    }
}

@available(macCatalyst 14.0, *)
struct BookDetailView_Previews: PreviewProvider {
    static var modelData = ModelData()
    @State static var book = CalibreBook(id: 1, library: CalibreLibrary(server: CalibreServer(baseUrl: "", username: "", password: ""), name: "Local"), title: "Title", authors: "Author", comments: "", rating: 0, formats: ["EPUB":""], readPos: BookReadingPosition(), inShelf: true)
    static var previews: some View {
        BookDetailView(book: $book)
            .environmentObject(modelData)
    }
}
