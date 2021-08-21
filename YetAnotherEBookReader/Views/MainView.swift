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

    var body: some View {
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
        .fullScreenCover(isPresented: $modelData.presentingEBookReaderFromShelf, onDismiss: {
            modelData.presentingEBookReaderFromShelf = false
            guard let readerInfo = modelData.readerInfo else { return }
            let originalPosition = readerInfo.position
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
            return Alert(title: Text(item.id), message: Text(item.msg ?? "Unexpected Error"))
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
