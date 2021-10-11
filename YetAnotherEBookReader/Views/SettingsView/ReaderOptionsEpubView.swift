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
                Text("★How to supply fonts").bold()
                Text("Place font files inside \"Fonts\" folder of this App. They will appear in \"Font\" tab of Reader's style menu.")
                Text("Currently supports TrueType (.ttf) and OpenType (.otf).")
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
    static var previews: some View {
        ReaderOptionsEpubView()
    }
}
