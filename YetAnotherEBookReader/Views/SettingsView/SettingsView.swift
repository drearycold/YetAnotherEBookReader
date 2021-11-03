//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/13.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var modelData: ModelData
    
    var body: some View {
        VStack {
        NavigationView {
            List {
                NavigationLink(destination: ServerView()) {
                    Text("Server & Library")
                    if modelData.booksInShelf.isEmpty {
                        Text("Start here").foregroundColor(.red)
                    }
                }.padding([.top, .bottom], 8)
                NavigationLink("Reader Options", destination: ReaderOptionsView())
                    .padding([.top, .bottom], 8)
                HStack{}.frame(height: 4)
                NavigationLink("Reading Statistics", destination: ReadingPositionHistoryView(libraryId: nil, bookId: nil))
                    .padding([.top, .bottom], 8)
                NavigationLink("Activity Logs", destination: ActivityList())
                    .padding([.top, .bottom], 8)
                HStack{}.frame(height: 4)
                NavigationLink("Version History", destination: VersionHistoryView())
                    .padding([.top, .bottom], 8)
                NavigationLink("Support", destination: SupportInfoView())
                    .padding([.top, .bottom], 8)
                NavigationLink("About", destination: AppInfoView())
                    .padding([.top, .bottom], 8)
            }.environment(\.defaultMinListRowHeight, 8)
            
        }.navigationViewStyle(StackNavigationViewStyle())
            Spacer()
            HStack {
                Text("Version \(modelData.resourceFileDictionary?.value(forKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                Text("Build \(modelData.resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1")")
            }.font(.caption).foregroundColor(.gray)
        }
        
    }
}

struct SettingsView_Previews: PreviewProvider {
    static private var modelData = ModelData()

    static var previews: some View {
        SettingsView()
            .environmentObject(modelData)
    }
}
