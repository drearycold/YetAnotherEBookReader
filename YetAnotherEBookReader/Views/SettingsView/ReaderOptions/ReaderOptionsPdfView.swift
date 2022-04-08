//
//  OptionsPDFView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/9.
//

import SwiftUI

struct ReaderOptionsPdfView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
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
            }.padding()
        }
    }
}

struct ReaderOptionsPdfView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsPdfView()
    }
}
