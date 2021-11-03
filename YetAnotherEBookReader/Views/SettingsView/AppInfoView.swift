//
//  ReportView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/11.
//

import SwiftUI

struct AppInfoView: View {
    @EnvironmentObject var modelData: ModelData

    @Environment(\.openURL) var openURL

    private let calibreURL = "https://calibre-ebook.com/"
    private let folioReaderKitURL = "https://github.com/FolioReader/FolioReaderKit"
    private let readiumURL = "https://github.com/readium/awesome-readium"
    private let shelfViewURL = "https://github.com/tdscientist/ShelfView-iOS"
    private let ozzyURL = "https://github.com/cfhamlet"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 8) {
                VStack(alignment: .center, spacing: 16) {
                    Text("D.S.Reader").font(.title)
                    
                    Image("logo_1024")
                        .resizable().frame(width: 256, height: 256, alignment: .center)
                    Text("by Drearycold & Siyi")
//                    HStack {
//                        Text("Version \(modelData.resourceFileDictionary?.value(forKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
//                        Text("Build \(modelData.resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1")")
//                    }
                }
                
                VStack(spacing: 8) {
                    Text("Special Thanks to")
                    VStack(spacing: 4) {
                        linkButtonBuilder(title: "calibre", url: calibreURL)
                        linkButtonBuilder(title: "cfhamlet (Ozzy)", url: ozzyURL)
                    }
                    VStack(spacing: 4) {
                        linkButtonBuilder(title: "FolioReaderKit Project", url: folioReaderKitURL)
                        linkButtonBuilder(title: "Readium Project", url: readiumURL)
                        linkButtonBuilder(title: "ShelfView (iOS) Project", url: shelfViewURL)
                    }

                }
            }.padding()
            .frame(maxWidth: 500)
        }
    }
    
    @ViewBuilder
    private func linkButtonBuilder(title: String, url: String) -> some View {
        Button(action:{
            openURL(URL(string: url)!)
        }) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "square.and.arrow.up")
            }.padding([.leading, .trailing], 32)
        }
    }
}

struct ReportView_Previews: PreviewProvider {
    static private var modelData = ModelData()

    static var previews: some View {
        AppInfoView()
            .environmentObject(modelData)
    }
}
