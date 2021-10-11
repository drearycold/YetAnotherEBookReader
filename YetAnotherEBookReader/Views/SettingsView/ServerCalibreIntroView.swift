//
//  ServerCalibreIntroView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/11.
//

import SwiftUI

struct ServerCalibreIntroView: View {
    @Environment(\.openURL) var openURL

    private var calibreDownloadURL = "https://calibre-ebook.com/download"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's calibre server?")
                    .font(.title3)
                Text("To quote:")
                VStack(alignment: .leading, spacing: 4) {
                Text("\"calibre is a powerful and easy to use e-book manager. Users say it’s outstanding and a must-have. It’ll allow you to do nearly everything and it takes things a step beyond normal e-book software. It’s also completely free and open source and great for both casual users and computer experts.\"")
                Text("\"The calibre Content server allows you to access your calibre libraries and read books directly in a browser on your favorite mobile phone or tablet device. As a result, you do not need to install any dedicated book reading/management apps on your phone. Just use the browser. The server downloads and stores the book you are reading in an off-line cache so that you can read it even when there is no internet connection.\"")
                }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                Text("Download and install on Windows/macOS/Linux from")
                Button(action:{
                    openURL(URL(string: calibreDownloadURL)!)
                }) {
                    Image(systemName: "square.and.arrow.up")
                    Text(calibreDownloadURL)
                }
                Text("")
                Text("Prepare for Remote Access")
                    .font(.title3)
                Text(
"""
This App utilizes calibre Content server API to provide better integration with calibre and richer experiences. To enable remote access to calibre, you need to:
 • Required:
     (under "Connect/share" toolbar item)
   ◦ Start Content Server
 • Recommended:
     (under "Preferences -> Sharing over the net")
   ◦ Enable "Run server automatically when calibre starts"
   ◦ Enable "Require username and password to access the Content server" to allow making changes to library, then setup user accounts
 • Advanced:
   ◦ Config SSL to enable HTTPS for maximum protection, especially when server is exposed to Internet
   ◦ Futher steps are required if you are using self-signed certificates
   ◦ We believe you can figure out yourself 😁 (instructions on the road)
"""
                )
                Button(action: {
                    openURL(URL(string: "https://manual.calibre-ebook.com/server.html")!)
                }) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Manual of Content server")
                }
            }
            .padding()
        }
    }
}

struct ServerCalibreIntroView_Previews: PreviewProvider {
    static var previews: some View {
        ServerCalibreIntroView()
    }
}
