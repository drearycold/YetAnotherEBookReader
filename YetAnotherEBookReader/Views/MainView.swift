//
//  MainView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI

@available(macCatalyst 14.0, *)
struct MainView: View {
    @EnvironmentObject var modelData: ModelData
    
    struct AlertItem : Identifiable {
        var id: String
        var msg: String?
    }
    @State private var alertItem: AlertItem?
    
    var body: some View {
        TabView(selection: $modelData.activeTab) {
            PlainShelfUI()
                .fullScreenCover(isPresented: $modelData.presentingEBookReaderForPlainShelf, onDismiss: { modelData.presentingEBookReaderForPlainShelf = false }) {
                    if let book = modelData.readingBook,
                       let bookFormatRaw = book.formats.first?.key,
                       let bookFormat = CalibreBook.Format(rawValue: bookFormatRaw),
                       let bookFormatReaderType = modelData.formatReaderMap[bookFormat]?.first,
                       let bookFileUrl = getSavedUrl(book: book, format: bookFormat)
                       {
                        YabrEBookReader(
                            bookURL: bookFileUrl,
                            bookFormat: bookFormat,
                            bookReader: bookFormatReaderType
                        )
                    } else {
                        Text("Nil Book")
                    }
                }
                .onChange(of: modelData.presentingEBookReaderForPlainShelf) { presenting in
                    guard presenting == false else {
                        return
                    }
                    let originalPosition = modelData.getLatestReadingPosition() ?? modelData.getInitialReadingPosition()
                    if modelData.updatedReadingPosition.isSameProgress(with: originalPosition) {
                        return
                    }
                    if modelData.updatedReadingPosition < originalPosition {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            alertItem = AlertItem(id: "BackwardProgress", msg: "Previous \(originalPosition.description) VS Current \(modelData.updatedReadingPosition.description)")
                        }
                    } else if originalPosition << modelData.updatedReadingPosition {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            alertItem = AlertItem(id: "ForwardProgress", msg: "Previous \(originalPosition.description) VS Current \(modelData.updatedReadingPosition.description)")
                        }
                    }
                    else {
                        modelData.updateCurrentPosition()
                    }
                }
                .alert(item: $alertItem) { item in
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
                    return Alert(title: Text(item.id))
                }
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text("Local")
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
                    Text("Library")
                }
                .tag(2)
            
            ServerView()
                .tabItem {
                    Image(systemName: "server.rack")
                    Text("Server")
                }
                .tag(3)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .font(.headline)
        .onOpenURL { url in
            print("onOpenURL \(url)")
            modelData.onOpenURL(url: url)
        }
        
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
