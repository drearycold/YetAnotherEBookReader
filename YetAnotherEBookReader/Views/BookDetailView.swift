//
//  BookView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import Foundation
import OSLog
import SwiftUI

@available(macCatalyst 14.0, *)
struct BookDetailView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.managedObjectContext) private var viewContext
    var defaultLog = Logger()
    
    
    @Binding var book: Book
    //    var currentReadingPosition = BookDeviceReadingPosition(id: "")
    //    @State private var bookTitle = ""
    //    @State private var bookAuthors = ""
    //    @State private var bookComments = ""
    @State private var readingPositions = [String]()
    @State private var showingAlert = false
    @State private var showingRefreshAlert = false
    @State private var showingDownloadAlert = false
    @State private var selectedFormat = Book.Format.EPUB
    
    var commentWebView = WebViewUI()
    
    let rvc = ReaderViewController()
    var pdfView = PDFViewUI()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                HStack {
                    //TextField("Title", text: $book.title).font(.title)
                    Text(book.title).font(.title)
                    Spacer()
                }
                HStack {
                    Text(book.authors).font(.subheadline)
                    Spacer()
                }
                
                Picker("Format", selection: $selectedFormat) {
                    ForEach(Book.Format.allCases) { format in
                        if book.formats[format.rawValue] != nil {
                            Text(format.rawValue).tag(format)
                        }
                    }
                }.pickerStyle(WheelPickerStyle())
                
                ForEach(readingPositions, id: \.self) { position in
                    Text(position)
                }
                
                HStack {
                    Spacer()
                    Button(action: {getMetadata()}) {
                        Text("Refresh")
                    }
                    Spacer()
                    Button(action: {downloadFormat(book: book, format: selectedFormat)}) {
                        Text("Download")
                    }
                    Spacer()
                    Button(action: {clearCache(book: book)}) {
                        Text("Clear")
                    }
                    Spacer()
                    Button(action: {readFormat(book: book, format: selectedFormat)}) {
                        Text("Read")
                    }.alert(isPresented: Binding<Bool>(
                        get: {
                            self.showingAlert
                        },
                        set: {
                            self.showingAlert = $0
                            self.showingRefreshAlert = false
                            self.showingDownloadAlert = false
                        }
                    )) {
                        if showingRefreshAlert
                        {
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
                        if showingDownloadAlert
                        {
                            return Alert(
                                title: Text("Need Download"),
                                message: Text("Please Download First"),
                                primaryButton: .default(Text("Download"), action: {
                                    downloadFormat(book: book, format: selectedFormat)
                                }),
                                secondaryButton: .cancel()
                            )
                        }
                        return Alert(title: Text("Dummy"))
                    }
                    Spacer()
                }
                rvc.frame(width: CGFloat(100), height: CGFloat(1), alignment: .center)
                pdfView.frame(width: CGFloat(100), height: CGFloat(1), alignment: .center)
                commentWebView.frame(width: CGFloat(400), height: CGFloat(400), alignment: .center)

            }
        }
    }
    
    func getMetadata() {
        let endpointUrl = URL(string: modelData.calibreServer + "/cdb/cmd/list/0?library_id=" + book.libraryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
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
                        
                        commentWebView.setContent(book.comments, URL(string: modelData.calibreServer))
                        
                        readingPositions.removeAll()
                        book.readPos.getDevices().forEach { position in
                            readingPositions.append("\(position.id) with \(position.readerName): \(position.lastPosition[0]) \(position.lastPosition[1]) \(position.lastPosition[2]) \(position.lastReadPage)")
                        }
                        
                        Book.Format.allCases.forEach { format in
                            if book.formats[format.rawValue] != nil {
                                selectedFormat = format
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
                //                bookTitle = book.title
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
                //                bookComments = book.comments
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
    
    func downloadFormat(book: Book, format: Book.Format) {
        let url = URL(string: modelData.calibreServer + "/get/\(format.rawValue)/\(book.id)/\(book.libraryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")
        let downloadTask = URLSession.shared.downloadTask(with: url!) {
            urlOrNil, responseOrNil, errorOrNil in
            // check for and handle errors:
            // * errorOrNil should be nil
            // * responseOrNil should be an HTTPURLResponse with statusCode in 200..<299
            
            guard let fileURL = urlOrNil else { return }
            do {
                let downloadBaseURL = try
                    FileManager.default.url(for: .cachesDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: false)
                if !FileManager.default.fileExists(atPath: downloadBaseURL.path) {
                    try FileManager.default.createDirectory(atPath: downloadBaseURL.path, withIntermediateDirectories: true)
                }
                let savedURL = downloadBaseURL.appendingPathComponent("\(book.libraryName) - \(book.id).\(format.rawValue.lowercased())")
                
                defaultLog.info("fileURL: \(fileURL.absoluteString)")
                defaultLog.info("savedURL: \(savedURL.absoluteString)")
                if FileManager.default.fileExists(atPath: savedURL.path) {
                    try FileManager.default.removeItem(at: savedURL)
                }
                try FileManager.default.moveItem(at: fileURL, to: savedURL)
                
                let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
                defaultLog.info("isFileExist: \(isFileExist)")
            } catch {
                print ("file error: \(error)")
            }
        }
        downloadTask.resume()
    }
    
    func clearCache(book: Book) {
        do {
            let documentURL = try FileManager.default.url(for: .documentDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil,
                                                          create: false)
            let savedURL = documentURL.appendingPathComponent("\(book.libraryName) - \(book.id).epub")
            let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
            if( isFileExist) {
                try FileManager.default.removeItem(at: savedURL)
            }
        } catch {
            defaultLog.error("clearCache \(error.localizedDescription)")
        }
    }
    
    func readFormat(book: Book, format: Book.Format) {
        if(book.readPos.isEmpty) {
            self.showingRefreshAlert = true
            self.showingAlert = true
            return
        }
        
        do {
            let downloadBaseURL = try
                FileManager.default.url(for: .cachesDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil,
                                        create: false)
            let savedURL = downloadBaseURL.appendingPathComponent("\(book.libraryName) - \(book.id).\(format.rawValue.lowercased())")
            let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
            if (!isFileExist) {
                self.showingDownloadAlert = true
                self.showingAlert = true
                return
            }
            
            defaultLog.info("downloadBaseURL: \(downloadBaseURL.absoluteString)")
            defaultLog.info("savedURL: \(savedURL.absoluteString)")
            
            
            modelData.isReading = true;
            if(format == Book.Format.EPUB) {
                rvc.openBook(savedURL, self)
            }
            if( format == Book.Format.PDF) {
                pdfView.open(pdfURL: savedURL, bookDetailView: self)
            }
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
            
            book.readPos.updatePosition(deviceName, deviceReadingPosition!)
            
            var deviceMapSerialize = [String: Any]()
            try book.readPos.getCopy().forEach { key, value in
                deviceMapSerialize[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            }
            
            
            let readPosData = try JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []).base64EncodedString()
            
            let endpointUrl = URL(string: modelData.calibreServer + "/cdb/cmd/set_metadata/0?library_id=" + book.libraryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
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
            
        }catch{
        }
        
        modelData.isReading = false
    }
}

@available(macCatalyst 14.0, *)
struct BookDetailView_Previews: PreviewProvider {
    static var modelData = ModelData()
    @State static var book = Book()
    static var previews: some View {
        BookDetailView(book: $book)
            .environmentObject(modelData)
    }
}
