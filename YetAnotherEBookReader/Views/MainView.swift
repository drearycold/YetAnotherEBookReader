//
//  MainView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI
import Combine

@available(macCatalyst 14.0, *)
struct MainView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.openURL) var openURL

    @State private var alertItem: AlertItem?

    @State private var positionActionPresenting = false
    @State private var positionActionMessage = ""
    
    @State private var bookImportedCancellable: AnyCancellable?
    @State private var dismissAllCancellable: AnyCancellable?

    @State private var bookImportActionSheetPresenting = false
    @State private var bookImportInfo: BookImportInfo?
    
    private let issueURL = "https://github.com/drearycold/YetAnotherEBookReader/issues/new?labels=bug&assignees=drearycold"

    var body: some View {
        ZStack {
            TabView(selection: $modelData.activeTab) {
                RecentShelfUI()
                    .tabItem {
                        Image(systemName: "doc.text.fill")
                        Text("Recent")
                    }
                    .tag(0)
                    
                SectionShelfUI()
                    .tabItem {
                        Image(systemName: "books.vertical.fill")
                        Text("Shelf")
                    }
                    .tag(1)
                
                LibraryInfoView()
                    .tabItem {
                        Image(systemName: "building.columns.fill")
                        Text("Browse")
                    }
                    .tag(2)
                
                SettingsView()
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .tag(3)
            }
            if modelData.activeTab < 2 && modelData.calibreServerLibraryUpdating {
                ProgressView("Initializing Library...")
                    .background(Color.gray.opacity(0.4).cornerRadius(16).frame(minWidth: 300, minHeight: 360))
            }
            if modelData.activeTab < 3 && modelData.booksInShelf.filter({$0.value.library.server.isLocal == false}).isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Welcome!")
                        
                    Text("""
                        Get start from
                        \"Settings\" -> \"Server & Library\"
                        to link with Calibre Server.
                        """)
                        
                    Text("""
                        Then go to "Browse"
                        to add book to Shelf by toggling \(Image(systemName: "star"))
                        or by downloading (\(Image(systemName: "tray.and.arrow.down"))) individual format.
                        """)
                        
                    Text("Start reading by touching book cover.")
                        
                    Text("Don't forget to play with \"Reader Options\" and various in-reader settings.")
                        
                    Text("Enjoy your book!")
                        
                    Text("(This notice will disappear after first book has been added to shelf)")
                        
                }
                .multilineTextAlignment(.leading)
                .padding()
                .background(Color.gray.opacity(0.5).cornerRadius(16).frame(minWidth: 300, minHeight: 360))
                .frame(maxWidth: 400)
            }
        }
        .fullScreenCover(isPresented: $modelData.presentingEBookReaderFromShelf, onDismiss: {
            modelData.presentingEBookReaderFromShelf = false
            guard let readerInfo = modelData.readerInfo else { return }
            let originalPosition = readerInfo.position
            if modelData.updatedReadingPosition.isSameProgress(with: originalPosition) {
                return
            }
            if false && modelData.updatedReadingPosition < originalPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    alertItem = AlertItem(
                        id: "BackwardProgress",
                        msg: "You have reached a position behind last saved, is this alright?"
                    )
                }
            } else if false && originalPosition << modelData.updatedReadingPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    alertItem = AlertItem(
                        id: "ForwardProgress",
                        msg: "You have advanced more than 10% in this book, is this alright?"
                    )
                }
            }
            else {
                modelData.updateCurrentPosition(alertDelegate: self)
            }
        }) {
            if let readerInfo = modelData.readerInfo {
                YabrEBookReader(readerInfo: readerInfo)
            } else {
                Text("No Suitable Format/Reader/Position Combo")
            }
        }
//        .alert(item: $alertItem) { item in
//            if item.id == "ForwardProgress" || item.id == "BackwardProgress" {
//                return Alert(
//                    title: Text("Confirm New Progress"),
//                    message: Text(item.msg ?? ""),
//                    primaryButton: .destructive(Text("Confirm")) {
//                        modelData.updateCurrentPosition(alertDelegate: self)
//                    },
//                    secondaryButton: .cancel()
//                )
//            } else {
//                return Alert(
//                    title: Text(item.id),
//                    message: Text(item.msg ?? ""),
//                    primaryButton: .default(Text("OK"), action: item.action),
//                    secondaryButton: .cancel()
//                )
//            }
//        }
        .actionSheet(isPresented: $bookImportActionSheetPresenting, content: {
            guard let bookImportInfo = bookImportInfo else {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Unexpected error occured (code empty result). Please consider report this."),
                    buttons: [
                        .default(Text("Report"), action: {
                            openURL(URL(string: issueURL + "&title=Error+Importing+Book+Empty+Result&body=")!)
                        }),
                        .cancel()])
            }
            if bookImportInfo.error == nil, let bookId = bookImportInfo.bookId {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Imported, read now?"),
                    buttons: [
                        .default(Text("Read"), action: {
                            guard let localLibrary = modelData.localLibrary else { return }
                            let book = CalibreBook(id: bookId, library: localLibrary)
                            modelData.readingBookInShelfId = book.inShelfId
                            modelData.presentingEBookReaderFromShelf = true
                        }),
                        .cancel()
                    ]
                )
            }
            if bookImportInfo.error == .destConflict {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Book of same file name already exists. Do you wish to overwrite existing one?"),
                    buttons: [
                        .default(Text("As a new book"), action: {
                            let result = modelData.onOpenURL(url: bookImportInfo.url, doMove: false, doOverwrite: false, asNew: true, knownBookId: bookImportInfo.bookId)
                            NotificationCenter.default.post(name: Notification.Name("YABR.bookImported"), object: nil, userInfo: ["result": result])
                        }),
                        .destructive(Text("Overwrite"), action: {
                            let result = modelData.onOpenURL(url: bookImportInfo.url, doMove: false, doOverwrite: true, asNew: false, knownBookId: bookImportInfo.bookId)
                            NotificationCenter.default.post(name: Notification.Name("YABR.bookImported"), object: nil, userInfo: ["result": result])
                        }),
                        .cancel()
                    ]
                )
            }
            return ActionSheet(
                title: Text("Importing"),
                message: Text("Unexpected error occured (code \(bookImportInfo.error?.rawValue ?? "unknown")). Please consider report this."),
                buttons: [
                    .default(Text("Report"), action: {
                        openURL(URL(string: issueURL + "&title=Error+Importing+Book+\(String(describing: bookImportInfo.error))&body=")!)
                    }),
                    .cancel()])
        })
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .font(.headline)
        .onOpenURL { url in
            print("onOpenURL \(url)")
            let result = modelData.onOpenURL(url: url, doMove: false, doOverwrite: false, asNew: false)
            
            NotificationCenter.default.post(name: Notification.Name("YABR.bookImported"), object: nil, userInfo: ["result": result])
        }.onAppear {
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllPublisher.sink { _ in
                modelData.presentingEBookReaderFromShelf = false
                positionActionPresenting = false
            }

            bookImportedCancellable?.cancel()
            bookImportedCancellable = modelData.bookImportedPublisher.sink { notification in
                print("bookImportedCancellable sink \(notification)")
                guard let info = notification.userInfo?["result"] as? BookImportInfo else { return }
                bookImportInfo = info
                
                print("dismissAll \(modelData.presentingStack.count)")
                dismissAll() {
                    NotificationCenter.default.post(name: .YABR_DismissAll, object: nil)
                    modelData.activeTab = 0

                    bookImportActionSheetPresenting = false
                    DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(250))) {
                        bookImportActionSheetPresenting = true
                    }
                }
            }
        }
        
    }
    
    private func dismissAll(completion: @escaping () -> Void) {
        print("dismissAll \(modelData.presentingStack)")
        
        if let latest = modelData.presentingStack.last {
            if latest.wrappedValue == true {
                latest.wrappedValue = false
                print("dismissAll dismissed \(latest)")
                DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(250))) {
                    dismissAll(completion: completion)
                }
            } else {
                print("dismissAll already dismissed \(latest)")
                _ = modelData.presentingStack.popLast()
                dismissAll(completion: completion)
            }
        } else {
            completion()
        }
    }
    
}

extension MainView: AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

@available(macCatalyst 14.0, *)
struct MainView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        MainView()
            .environmentObject(modelData)
        // ReaderView()
    }
}
