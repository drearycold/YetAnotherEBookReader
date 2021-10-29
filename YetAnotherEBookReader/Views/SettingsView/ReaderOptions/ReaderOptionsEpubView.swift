//
//  ReaderOptionsEpubView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/9.
//

import SwiftUI

struct ReaderOptionsEpubView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("About \(ReaderType.YabrEPUB.rawValue)")
                    .font(.title3).bold()
                Text("""
                    Based on FolioReaderKit. Distinct features include:
                    • User Supplied Fonts
                    • Highly Customizable
                    • Highlight Syncing with Calibre
                    Try it Out! And let us know what you think.
                    """)
                Text("")
                Text("About \(ReaderType.ReadiumEPUB.rawValue)")
                    .font(.title3).bold()
                Text("""
                    Based on Readium Project. Could have better compatibility than YabrEPUB.
                    """)
            }
            
            .padding()
        }
    }
}


struct ReaderOptionsEpubView_Previews: PreviewProvider {
    static var modelData = ModelData(mock: true)

    static var previews: some View {
        ReaderOptionsEpubView()
            .environmentObject(modelData)
    }
}
