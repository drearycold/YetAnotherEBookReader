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
        NavigationView {
            List {
                NavigationLink(destination: ServerView()) {
                    Text("Server & Library")
                    if modelData.booksInShelf.isEmpty {
                        Text("Start here").foregroundColor(.red)
                    }
                }
                NavigationLink("Reader Options", destination: ReaderOptionsView())
                Text("")
                NavigationLink("Activity Logs", destination: ActivityList())
                NavigationLink("Support", destination: SupportInfoView())
                NavigationLink("About", destination: AppInfoView())
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct SettingsView_Previews: PreviewProvider {
    static private var modelData = ModelData()

    static var previews: some View {
        SettingsView()
            .environmentObject(modelData)
    }
}
