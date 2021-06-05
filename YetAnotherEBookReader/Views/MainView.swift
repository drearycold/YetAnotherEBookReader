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
        .fullScreenCover(isPresented: $modelData.presentingEBookReaderFromShelf, onDismiss: { modelData.presentingEBookReaderFromShelf = false }) {
            
            if let book = modelData.readingBook,
               let readerInfo = prepareBookReading(book: book)
               {
                YabrEBookReader(
                    bookURL: readerInfo.0,
                    bookFormat: readerInfo.1,
                    bookReader: readerInfo.2
                )
            } else {
                Text("Nil Book")
            }
        }
        .onChange(of: modelData.presentingEBookReaderFromShelf) { presenting in
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .font(.headline)
        .onOpenURL { url in
            print("onOpenURL \(url)")
            modelData.onOpenURL(url: url)
        }
        
    }
    
    func prepareBookReading(book: CalibreBook) ->(URL, CalibreBook.Format, ReaderType)? {
        guard let position = modelData.getSelectedReadingPosition() else { return nil }
        
        let formatReaderPairArray = modelData.formatReaderMap.compactMap {
            guard let index = $0.value.firstIndex(where: { $0.rawValue == position.readerName }) else { return nil }
            return ($0.key, $0.value[index])
        } as [(CalibreBook.Format, ReaderType)]
        
        guard let formatReaderPair = formatReaderPairArray.first else { return nil }
        guard let savedURL = getSavedUrl(book: book, format: formatReaderPair.0) else { return nil }
        
        return (savedURL, formatReaderPair.0, formatReaderPair.1)
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
