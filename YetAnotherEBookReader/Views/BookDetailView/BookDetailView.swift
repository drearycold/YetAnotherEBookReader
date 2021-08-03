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
    
    @State private var downloadStatus = DownloadStatus.INITIAL
    
    var defaultLog = Logger()
    
    @State private var alertItem: AlertItem?

//    @State private var presentingUpdateAlert = false
//    @State private var showingRefreshAlert = false
//    @State private var showingDownloadAlert = false
    
    @State private var formatStats = [Format: FormatInfo]()
    
    @State private var selectedFormatShowDetail = false
    @State private var selectedFormat = Format.EPUB
//    @State private var selectedFormatSize:UInt64 = 0
//    @State private var selectedFormatMTime = Date()
//    @State private var selectedFormatCached = false
//    @State private var selectedFormatCachedSize:UInt64 = 0
//    @State private var selectedFormatCachedMTime = Date()
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
                .navigationTitle(Text(modelData.readingBook?.title ?? ""))
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
//            if item.id == "Download" {
//                return Alert(
//                    title: Text("Need Download"),
//                    message: Text("Please Download First"),
//                    primaryButton: .default(Text("Download"), action: {
//                        modelData.downloadFormat(book: modelData.readingBook!, format: selectedFormat, modificationDate: selectedFormatMTime) { result in
//
//                        }
//                    }),
//                    secondaryButton: .cancel()
//                )
//            }
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
                    modelData.updateCurrentPosition(alertDelegate: self)
                }), secondaryButton: .cancel())
            }
            if item.id == "BackwardProgress" {
                return Alert(title: Text("Confirm Backwards Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    modelData.updateCurrentPosition(alertDelegate: self)
                }), secondaryButton: .cancel())
            }
            if item.id == "ReadingPosition" {
                return Alert(title: Text("Confirm Reading Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    let selectedPosition = modelData.getSelectedReadingPosition()
                    readBook(position: selectedPosition!)
                }), secondaryButton: .cancel())
            }
            return Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .fullScreenCover(isPresented: $showingReadSheet, onDismiss: {showingReadSheet = false} ) {
            if let readerInfo = modelData.readerInfo {
                YabrEBookReader(readerInfo: readerInfo)
            } else {
                Text("Nil Book")
            }
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
                VStack(alignment: .center, spacing: 8) {
                    KFImage(book.coverURL)
                        .placeholder {
                            Text("Loading Cover ...")
                        }
                    metadataViewContent(book: book, isCompat: isCompat)
                }
            } else {
                HStack(alignment: .top, spacing: 32) {
                    KFImage(book.coverURL)
                        .placeholder {
                            Text("Loading Cover ...")
                        }
                    metadataViewContent(book: book, isCompat: isCompat)
                }
            }
            
            
            #if canImport(GoogleMobileAds)
            Banner()
            #endif
            
            VStack(alignment: .center, spacing: 8) {
                HStack {
                    Text("Shelf")
                        .font(.subheadline)
                        .frame(minWidth: 80, alignment: .trailing)
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
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))

                if shelfNameShowDetail {
                    Toggle("Customize Shelf Name", isOn: $shelfNameCustomized)
                }
            
                HStack {
                    Text("Read At")
                        .font(.subheadline)
                        .frame(minWidth: 80, alignment: .trailing)
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
                    .onChange(of: selectedPosition) { value in
                        modelData.selectedPosition = selectedPosition
                        
                        if let position = book.readPos.getPosition(selectedPosition),
                           let format = modelData.formatOfReader(readerName: position.readerName) {
                            selectedFormat = format
                        }
                        
                        guard selectedFormat == Format.UNKNOWN
                                || book.formats.contains(where: { $0.key == selectedFormat.rawValue }) == false
                                else { return }
                        Format.allCases.forEach { format in
                            if formatStats[format]?.cached ?? false {
                                self.selectedFormat = format
                            }
                        }
                        
                        guard selectedFormat == Format.UNKNOWN
                                || book.formats.contains(where: { $0.key == selectedFormat.rawValue }) == false
                                else { return }
                        if book.formats[modelData.defaultFormat.rawValue] != nil {
                            self.selectedFormat = modelData.defaultFormat
                        }
                        
                        guard selectedFormat == Format.UNKNOWN
                                || book.formats.contains(where: { $0.key == selectedFormat.rawValue }) == false
                                else { return }
                        Format.allCases.forEach { format in
                            if book.formats[format.rawValue] != nil {
                                self.selectedFormat = format
                            }
                        }
                    }
                    .onChange(of: modelData.updatedReadingPosition) { value in
                        if let selectedPosition = modelData.readerInfo?.position {
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
                                modelData.updateCurrentPosition(alertDelegate: self)
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
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))

                if selectedPositionShowDetail {
                    Text(modelData.getSelectedReadingPosition()?.description ?? modelData.getDeviceReadingPosition()?.description ?? modelData.deviceName)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 80)
                        .font(.subheadline)
                }
                
                HStack {
                    Text("Format")
                        .font(.subheadline)
                        .frame(minWidth: 80, alignment: .trailing)
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(Format.allCases) { format in
                            if book.formats[format.rawValue] != nil {
                                Text(format.rawValue).tag(format)
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedFormat) { newFormat in
                        if newFormat == Format.UNKNOWN {
                            return
                        }
                        print("selectedFormat \(selectedFormat.rawValue)")
                        
                        guard let readers = modelData.formatReaderMap[selectedFormat] else { return }
                        selectedFormatReader = readers.reduce(into: readers.first!) {
                            if $1.rawValue == book.readPos.getPosition(self.selectedPosition)?.readerName {
                                $0 = $1
                            }
                        }
                        
                        modelData.getBookManifest(book: book, format: newFormat) { manifest in
                            parseManifestToTOC(json: manifest)
                        }
                    }
                    
                    Button(action:{ selectedFormatShowDetail.toggle() }) {
                        if selectedFormatShowDetail {
                            Image(systemName: "chevron.up")
                        } else {
                            Image(systemName: "chevron.down")
                        }
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))

                if selectedFormatShowDetail, let formatInfo = formatStats[selectedFormat] {
                    viewContentFormatDetail(book: book, isCompat: isCompat, formatInfo: formatInfo)
                        .fixedSize()
                }
                
                HStack {
                    Text("Reader")
                        .font(.subheadline)
                        .frame(minWidth: 80, alignment: .trailing)
                    Picker("Reader", selection: $selectedFormatReader) {
                        ForEach(ReaderType.allCases) { type in
                            if let types = modelData.formatReaderMap[selectedFormat],
                               types.contains(type) {
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
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
                .padding(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 16))
            }
            
            WebViewUI(
                content: generateCommentWithTOC(comments: book.comments, toc: selectedFormatTOC),
                baseURL: book.commentBaseURL
            )
                .frame(height: CGFloat(400), alignment: .center)
            
        }   //VStack
        .fixedSize()
    }
    
    @ViewBuilder
    private func metadataViewContent(book: CalibreBook, isCompat: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
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
                    if let id = book.identifiers["goodreads"] {
                        Button(action:{
                            openURL(URL(string: "https://www.goodreads.com/book/show/\(id)")!)
                        }) {
                            metadataLinkIcon("icon-goodreads")
                        }
                    } else {
                        Button(action:{
                            openURL(URL(string: "https://www.goodreads.com/")!)
                        }) {
                            metadataLinkIcon("icon-goodreads")
                        }.hidden()
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
                
                HStack {
                    metadataIcon(systemName: "envelope.open")
                    Text(book.lastModifiedByLocale)
                }
            }
            .lineLimit(2)
            .font(.subheadline)
            .frame(maxWidth: 300)
//            Rectangle().frame(width: 32, height: 16).foregroundColor(.none).opacity(0)
            
            VStack(alignment: .leading, spacing: 8) {
                if modelData.updatingMetadataStatus == "Success" {
                    HStack {
                        metadataIcon(systemName: "checkmark.shield")
                        Text("In Sync with Server")
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
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(formatStats.enumerated().sorted { $0.element.key.rawValue < $1.element.key.rawValue }, id: \.element.key) { format in
                    HStack(alignment: .top, spacing: 4) {
                        metadataFormatIcon(format.element.key.rawValue)
                            .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .bottom, spacing: 24) {
                                Text(format.element.key.rawValue)
                                    .font(.subheadline)
                                    .frame(minWidth: 48, alignment: .leading)
                                cacheFormatButton(
                                    book: book,
                                    format: format.element.key,
                                    formatInfo: format.element.value
                                )
                                
                                clearFormatButton(
                                    book: book,
                                    format: format.element.key,
                                    formatInfo: format.element.value
                                ).disabled(!format.element.value.cached)
                            }
                            HStack {
                                Text(
                                    ByteCountFormatter.string(
                                        fromByteCount: Int64(format.element.value.serverSize),
                                        countStyle: .file
                                    )
                                )
                                if format.element.value.cached {
                                    Text(format.element.value.cacheUptoDate ? "Up to date" : "Server has update")
                                    Image(systemName: format.element.value.cacheUptoDate ? "hand.thumbsup" : "hand.thumbsdown")
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
    private func viewContentFormatDetail(book: CalibreBook, isCompat: Bool, formatInfo: FormatInfo) -> some View {
        if isCompat {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading) {
                    Text("Server File Info")
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(formatInfo.serverSize),
                            countStyle: .file
                        )
                    )
                    Text(formatInfo.serverMTime.description)
                }
                
                Divider()
                
                VStack(alignment: .leading) {
                    Text("Cached File Info")
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(formatInfo.cacheSize),
                            countStyle: .file
                        )
                    )
                    Text(formatInfo.cacheMTime.description)
                }
            }.font(.subheadline)
        } else {
            HStack {
                Text(
                    ByteCountFormatter.string(
                        fromByteCount: Int64(formatInfo.serverSize),
                        countStyle: .file
                    )
                )
                .font(.subheadline)
                Spacer()
                if formatInfo.cached {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(formatInfo.cacheSize), countStyle: .file)).font(.subheadline)
                }
            }
            HStack {
                Spacer()
                if formatInfo.cached {
                    Text(formatInfo.cacheMTime.description)
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
                            updateCacheStates(book: book, format: selectedFormat)
                        }
                    } catch {
                        print(error)
                    }
                }) {
                    Image(systemName: "wrench.and.screwdriver")
                }
                #endif
                cacheFormatButton(book: book, format: selectedFormat, formatInfo: formatInfo)
                clearFormatButton(book: book, format: selectedFormat, formatInfo: formatInfo)
                    .disabled(!formatInfo.cached)
            }
        }
    }
    
    private func cacheFormatButton(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> some View {
        Button(action:{
            modelData.clearCache(book: book, format: format)
            modelData.downloadFormat(
                book: book,
                format: format,
                modificationDate: formatInfo.serverMTime
            ) { success in
                DispatchQueue.main.async {
                    updateCacheStates(book: book, format: format)
                    if book.inShelf == false {
                        modelData.addToShelf(book.id, shelfName: book.tags.first ?? "Untagged")
                    }

                    if format == Format.EPUB {
                        removeFolioCache(book: book, format: format)
                    }
                }
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
            updateCacheStates(book: book, format: format)
            
            guard !formatStats.contains(where: { $0.value.cached }) else { return }
            modelData.removeFromShelf(inShelfId: book.inShelfId)
        }) {
            Image(systemName: "tray.and.arrow.up")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                alertItem = AlertItem(id: "Delete")
            }) {
                if viewMode == .LIBRARY {
                Image(systemName: "trash")
                    .accentColor(.red)
                } else {
                    EmptyView().hidden()
                }
            }.disabled(!modelData.updatingMetadataSucceed)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button(action: {
                if modelData.updatingMetadata {
                    //TODO cancel
                } else {
                    if let book = modelData.readingBook {
                        if let coverUrl = book.coverURL {
                            modelData.kfImageCache.removeImage(forKey: coverUrl.absoluteString)
                        }
                        resetStates()
                        modelData.getMetadataNew(oldbook: book) { newbook in
                            initStates(book: newbook)
                            modelData.getBookManifest(book: newbook, format: selectedFormat) { manifest in
                                self.parseManifestToTOC(json: manifest)
                            }
                        }
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
                    modelData.clearCache(inShelfId: book.inShelfId, selectedFormat)
                    modelData.removeFromShelf(inShelfId: book.inShelfId)
                    downloadStatus = .INITIAL
                    updateCacheStates(book: book, format: selectedFormat)
                } else if downloadStatus == .INITIAL, let formatInfo = formatStats[selectedFormat] {
                    let downloading = modelData.downloadFormat(book: book, format: selectedFormat, modificationDate: formatInfo.serverMTime) { isSuccess in
                        if isSuccess {
                            downloadStatus = .DOWNLOADED
                            updateCacheStates(book: book, format: selectedFormat)
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
        selectedFormat = Format.UNKNOWN
        selectedPosition = ""
        selectedFormatReader = ReaderType.UNSUPPORTED
        formatStats.removeAll()
    }
    
    func initStates(book: CalibreBook) {
        initCacheStates(book: book)
        
        shelfName = book.inShelfName.isEmpty ? book.tags.first ?? "Untagged" : book.inShelfName
        shelfNameCustomized = !book.tags.contains(shelfName)
        
        if let position = modelData.getDeviceReadingPosition() {
            self.selectedPosition = position.id
        } else if let position = modelData.getLatestReadingPosition() {
            self.selectedPosition = position.id
        } else {
            self.selectedPosition = modelData.getInitialReadingPosition().id
        }
        
        
    }
    
    func initCacheStates(book: CalibreBook) {
        book.formats.forEach { (fKey, fValStr) in
            guard let format = Format(rawValue: fKey) else { return }
            var formatInfo = FormatInfo(
                serverSize: 0,
                serverMTime: Date(timeIntervalSince1970: 0),
                cached: false,
                cacheSize: 0,
                cacheMTime: Date(timeIntervalSince1970: 0)
            )
            
            if let fValData = Data(base64Encoded: fValStr),
               let fVal = try? JSONSerialization.jsonObject(with: fValData, options: []) as? NSDictionary {
                if let sizeVal = fVal["size"] as? NSNumber {
                    formatInfo.serverSize = sizeVal.uint64Value
                }
                if let mtimeVal = fVal["mtime"] as? String {
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = ISO8601DateFormatter.Options.withInternetDateTime.union(.withFractionalSeconds)
                    if let mtime = dateFormatter.date(from: mtimeVal) {
                        formatInfo.serverMTime = mtime
                    }
                }
            }
            
            if let cacheInfo = modelData.getCacheInfo(book: book, format: format), (cacheInfo.1 != nil) {
                print("cacheInfo: \(cacheInfo.0) \(cacheInfo.1!) vs \(formatInfo.serverSize) \(formatInfo.serverMTime)")
                formatInfo.cached = true
                formatInfo.cacheSize = cacheInfo.0
                formatInfo.cacheMTime = cacheInfo.1!
            } else {
                formatInfo.cached = false
            }
            
            self.formatStats[format] = formatInfo
        }
    }
    
    func updateCacheStates(book: CalibreBook, format: Format) {
        guard let formatInfo = formatStats[format] else { return }
        
        if let cacheInfo = modelData.getCacheInfo(book: book, format: format), (cacheInfo.1 != nil) {
            print("cacheInfo: \(cacheInfo.0) \(cacheInfo.1!) vs \(formatInfo.serverSize) \(formatInfo.serverMTime)")
            formatStats[format]!.cached = true
            formatStats[format]!.cacheSize = cacheInfo.0
            formatStats[format]!.cacheMTime = cacheInfo.1!
        } else {
            formatStats[format]!.cached = false
        }
    }
    
    func readBook(position: BookDeviceReadingPosition) {
        guard formatStats[selectedFormat]?.cached ?? false else {
            alertItem = AlertItem(id: "Selected Format Not Cached", msg: "Please download \(selectedFormat.rawValue) first")
            return
        }
        modelData.updatedReadingPosition.update(with: position)
        
        if let book = modelData.readingBook,
           let bookFileUrl = getSavedUrl(book: book, format: selectedFormat),
           let position = modelData.getSelectedReadingPosition() {
            
            modelData.prepareBookReading(
                url: bookFileUrl,
                format: selectedFormat,
                readerType: selectedFormatReader,
                position: position
            )
            showingReadSheet = true
        }
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
    @State static var book = CalibreBook(
        id: 5410,
        library: CalibreLibrary(
            server: CalibreServer(
                name:"My Server",
                baseUrl: "http://calibre-server.lan:8080/",
                publicUrl: "",
                username: "",
                password: ""),
            key: "Local",
            name: "Local"
        ),
        title: "Title",
        authors: ["Author"],
        comments: "",
        rating: 0,
        formats: ["EPUB":""],
        readPos: BookReadingPosition(),
        inShelf: true
    )
   
    static var modelData = ModelData()
     
    static var previews: some View {
        BookDetailView(viewMode: .LIBRARY)
            .environmentObject(modelData)
            .onAppear() {
                modelData.readingBook = book
            }
    }
}
