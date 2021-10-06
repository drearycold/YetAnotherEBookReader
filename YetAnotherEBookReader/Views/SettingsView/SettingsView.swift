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
                NavigationLink("Server & Library", destination: ServerView())
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
    static var previews: some View {
        SettingsView()
    }
}
