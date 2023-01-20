//
//  ReaderOptionsHelpView.swift
//  YetAnotherEBookReader
//
//  Created by Peter Lee on 2023/1/20.
//

import SwiftUI

struct ReaderOptionsHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
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
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("About \(ReaderType.YabrPDF.rawValue)")
                        .font(.title3).bold()
                    Text("""
                    Based on native PDFKit, single page mode only. Distinct features include:
                    • Auto Center Page Content
                    • Right to Left Page Order
                    • Customizable Page Background Color
                    Try it Out! And let us know what you think.
                    """)
                    Text("")
                    Text("About \(ReaderType.ReadiumPDF.rawValue)")
                        .font(.title3).bold()
                    Text("""
                    Based on Readium Project. Could have better compatibility than YabrPDF.
                    """)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("About \(ReaderType.ReadiumCBZ.rawValue)")
                        .font(.title3).bold()
                    Text("""
                        Based on Readium Project.
                        """)
                }
            }
            .padding()
        }
    }
}

struct ReaderOptionsHelpView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsHelpView()
    }
}
