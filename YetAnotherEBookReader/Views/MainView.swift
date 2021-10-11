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
    
    @State private var alertItem: AlertItem?

    @State private var positionActionPresenting = false
    @State private var positionActionMessage = ""
    
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
                VStack {
                    Text("""
                        Welcome!
                        
                        Get start from
                        \"Settings\" -> \"Server & Library\"
                        to link with Calibre Server.
                        
                        Then go to "Browse"
                        to add book to Shelf by toggling \(Image(systemName: "star"))
                        or by downloading (\(Image(systemName: "tray.and.arrow.down"))) individual format.
                        
                        Start reading by touching book cover.
                        
                        Enjoy your book!
                        
                        (This notice will disappear after first book has been added to shelf)
                        """)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .background(Color.gray.opacity(0.5).cornerRadius(16).frame(minWidth: 300, minHeight: 360))
                        .frame(maxWidth: 400)
                }
            }
        }
        .fullScreenCover(isPresented: $modelData.presentingEBookReaderFromShelf, onDismiss: {
            modelData.presentingEBookReaderFromShelf = false
            guard let readerInfo = modelData.readerInfo else { return }
            let originalPosition = readerInfo.position
            if modelData.updatedReadingPosition.isSameProgress(with: originalPosition) {
                return
            }
            if modelData.updatedReadingPosition < originalPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    alertItem = AlertItem(
                        id: "BackwardProgress",
                        msg: "You have reached a position behind last saved, is this alright?"
                    )
                }
            } else if originalPosition << modelData.updatedReadingPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
        .alert(item: $alertItem) { item in
            Alert(
                title: Text("Confirm New Progress"),
                message: Text(item.msg ?? ""),
                primaryButton: .destructive(Text("Confirm")) {
                    modelData.updateCurrentPosition(alertDelegate: self)
                },
                secondaryButton: .cancel()
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .font(.headline)
        .onOpenURL { url in
            print("onOpenURL \(url)")
            modelData.onOpenURL(url: url)
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
