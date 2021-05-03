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
        var msg: String?
    }
    @State private var alertItem: AlertItem?

//    @State private var presentingUpdateAlert = false
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
                    modelData.getMetadata(oldbook: book)
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
                modelData.getMetadata(oldbook: book!)
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
            return Alert(title: Text(item.id))
        }
        .fullScreenCover(isPresented: $showingReadSheet, onDismiss: {showingReadSheet = false} ) {
            EpubReader(bookURL: getSavedUrl(book: modelData.readingBook!))
        }
//        .popover(isPresented: $presentingUpdateAlert) {
//            if modelData.updatingMetadata {
//                VStack {
//                    Text("Updating")
//                }.frame(width: 200, height: 100, alignment: .center)
//            } else {
//                VStack {
//                    Text("Updated")
//                    Text("modelData.updatingMetadataStatus")
//                }.frame(width: 200, height: 100, alignment: .center)
//            }
//        }
        .disabled(modelData.readingBook == nil)
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
                if modelData.updatingMetadata {
                    Text("Updating")
                    Button(action: {
                        
                    }) {
                        Image(systemName: "xmark")
                    }
                } else {
                    Text(modelData.updatingMetadataStatus)
                    Text(book.lastModified.description).font(.subheadline)
                }
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
            Button(action: {
                showingReadSheet = true
                
            }) {
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
