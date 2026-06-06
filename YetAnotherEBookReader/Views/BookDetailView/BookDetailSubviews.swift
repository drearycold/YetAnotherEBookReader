import SwiftUI
import KingfisherSwiftUI
import RealmSwift

struct BookCoverView: View {
    @EnvironmentObject var downloadManager: BookDownloadManager
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    
    @Binding var presentingReadingSheet: Bool
    @Binding var alertItem: AlertItem?

    var body: some View {
        ZStack {
            KFImage(book.coverURL)
                .placeholder {
                    Text("Loading Cover ...")
                }
                .resizable()
                .scaledToFit()
            Button(action: {
                guard downloadManager.activeDownloads.filter({ $1.isDownloading && $1.book.id == book.id }).isEmpty else { return }
                viewModel.readBook(book: book)
                if book.inShelf {
                    presentingReadingSheet = true
                }
            }) {
                if downloadManager.activeDownloads.filter({ $1.book.id == book.id && ($1.isDownloading || $1.resumeData != nil) }).isEmpty == false ||
                    book.formats.filter({ $0.value.selected == true && $0.value.cached == false }).isEmpty == false {
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
                if let readerInfo = viewModel.readerInfo {
                    YabrEBookReader(
                        book: book,
                        readerInfo: readerInfo
                    )
                }
            }
        }
        .frame(width: 300, height: 400)
    }
}

struct BookMetadataSection: View {
    @Environment(\.openURL) var openURL
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool
    
    @Binding var readingPositionHistoryViewPresenting: Bool

    var body: some View {
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
            
            Group {
                HStack {
                    metadataIcon(systemName: "envelope.open")
                    Text(book.lastModifiedByLocale)
                }
                
                BookProgressSection(viewModel: viewModel, book: book, lastUpdated: lastUpdated, isCompat: isCompat, readingPositionHistoryViewPresenting: $readingPositionHistoryViewPresenting)
                
                HStack {
                    metadataIcon(systemName: "books.vertical")
                    let pluginGoodreadsSync = book.library.pluginGoodreadsSyncWithDefault
                    if pluginGoodreadsSync.isEnabled, pluginGoodreadsSync.tagsColumnName.count > 0,
                       let shelves = book.userMetadatas[pluginGoodreadsSync.tagsColumnName.trimmingCharacters(in: CharacterSet(["#"]))] as? [String],
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
    
    private func metadataIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 24, alignment: .center)
    }
    
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
}

struct BookProgressSection: View {
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool
    
    @Binding var readingPositionHistoryViewPresenting: Bool

    var body: some View {
        HStack {
            Image(systemName: "text.book.closed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 24, alignment: .center)
            
            Button(action:{
                viewModel.prepareReadingPositionHistory(book: book)
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
                } else if let position = book.readPos.getPosition(viewModel.deviceName) ?? book.readPos.getDevices().first {
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
}

struct BookConnectivitySection: View {
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool
    
    @Binding var activityListViewPresenting: Bool
    @Binding var alertItem: AlertItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.updatingMetadataStatus == "Success" {
                HStack {
                    metadataIcon(systemName: "checkmark.shield")
                    Text("In Sync with Server")
                }
            } else if viewModel.updatingMetadataStatus == "Local File" {
                HStack {
                    metadataIcon(systemName: "doc")
                    Text("Local File")
                }
            } else if viewModel.updatingMetadataStatus == "Deleted" {
                HStack {
                    metadataIcon(systemName: "xmark.shield")
                    Text("Been Deleted on Server")
                }
            } else if viewModel.updatingMetadataStatus == "Updating" {
                HStack {
                    metadataIcon(systemName: "arrow.clockwise")
                    Text("Syncing with Server")
                }
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action:{
                        alertItem = AlertItem(id: "Sync Error", msg: viewModel.updatingMetadataStatus)
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
                        if let modelData = viewModel.sharedModelData {
                            ActivityList(presenting: $activityListViewPresenting, libraryId: book.library.id, bookId: book.id)
                                .environmentObject(modelData)
                                .environmentObject(modelData.downloadManager)
                                .environmentObject(modelData.sessionManager)
                                .environmentObject(modelData.fontsManager)
                                .environment(\.realmConfiguration, modelData.realmConf ?? Realm.Configuration.defaultConfiguration)
                        }
                    }
                })
            }
        }
    }
    
    private func metadataIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 24, alignment: .center)
    }
}

struct BookFormatList: View {
    @EnvironmentObject var downloadManager: BookDownloadManager
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool
    
    @Binding var presentingPreviewSheet: Bool

    var body: some View {
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
                    metadataFormatIcon(format.rawValue)
                        .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .bottom, spacing: 24) {
                            Text(format.rawValue)
                                .font(.subheadline)
                                .frame(minWidth: 48, alignment: .leading)
                            cacheFormatButton(book: book, format: format, formatInfo: formatInfo)
                                .disabled(downloadManager.activeDownloads.filter( { $1.book.id == book.id && $1.format == format && ($1.isDownloading || $1.resumeData != nil) } ).count > 0)
                            
                            clearFormatButton(book: book, format: format, formatInfo: formatInfo)
                                .disabled(!formatInfo.cached)
                            
                            previewFormatButton(book: book, format: format, formatInfo: formatInfo)
                                .disabled(!formatInfo.cached)
                        }
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(formatInfo.serverSize), countStyle: .file))
                            if let download = downloadManager.activeDownloads.filter( { $1.book.id == book.id && $1.format == format && ($1.isDownloading || $1.resumeData != nil) } ).first?.value {
                                ProgressView(value: download.progress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(maxWidth: 160)
                                
                                Button(action: {
                                    if download.isDownloading {
                                        viewModel.pauseDownload(book: book, format: format)
                                    } else {
                                        viewModel.resumeDownload(book: book, format: format)
                                    }
                                }) {
                                    Image(systemName: download.isDownloading ? "pause" : "play")
                                }
                                
                                Button(action:{
                                    viewModel.cancelDownload(book: book, format: format)
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
            viewModel.cacheFormat(book: book, format: format)
        }) {
            Image(systemName: "tray.and.arrow.down")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    private func clearFormatButton(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> some View {
        Button(action:{
            viewModel.clearFormat(book: book, format: format)
        }) {
            Image(systemName: "tray.and.arrow.up")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    private func previewFormatButton(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> some View {
        Button(action: {
            if viewModel.previewAction(book: book, format: format, formatInfo: formatInfo) {
                presentingPreviewSheet = true
            }
        }) {
            Image(systemName: "doc.text.magnifyingglass")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
        .sheet(isPresented: $presentingPreviewSheet, onDismiss: {
            viewModel.handlePreviewDismiss(book: book)
        }) {
            BookPreviewView(viewModel: viewModel.previewViewModel)
        }
    }
    
    private func metadataFormatIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
    }
}

struct BookCountPagesCorner: View {
    var book: CalibreBook
    var lastUpdated: Date
    var countPage: CalibreCountPagesPrefs.LibraryConfig
    var isCompat: Bool

    var body: some View {
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
}