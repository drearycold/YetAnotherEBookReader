//
//  ReportView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/11.
//

import SwiftUI

struct AppInfoView: View {
    @Environment(\.openURL) var openURL

    private let issueURL = "https://github.com/drearycold/YetAnotherEBookReader/issues"
    
    var body: some View {
        VStack(alignment: .center) {
            VStack(alignment: .center, spacing: 16) {
                Text("D&S Reader").font(.title)
                
                Image("logo_1024")
                    .resizable().frame(width: 256, height: 256, alignment: .center)
                Text("by Drearycold & Siyi")
                Text("Version 0.1.0")
            }
            
            List {
                Button(action:{
                    openURL(URL(string: issueURL)!)
                }) {
                    HStack {
                        Spacer()
                        Text("Report an Issue")
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                        Spacer()
                    }
                }
            }
        }.padding()
        .frame(maxWidth: 600)
    }
}

struct ReportView_Previews: PreviewProvider {
    static var previews: some View {
        AppInfoView()
    }
}
