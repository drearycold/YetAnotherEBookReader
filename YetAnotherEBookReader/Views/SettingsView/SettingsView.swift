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
                    if modelData.calibreServers.filter({$0.value.isLocal == false}).isEmpty {
                        Text("Start here").foregroundColor(.red)
                    }
                }
                NavigationLink("Reader Options", destination: ReaderOptionsView())
                Text("")
                NavigationLink("Licenses", destination: Text("Licenses"))
                NavigationLink("Report an issue", destination: Text("Report"))
                NavigationLink("About", destination: Text("About"))
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
