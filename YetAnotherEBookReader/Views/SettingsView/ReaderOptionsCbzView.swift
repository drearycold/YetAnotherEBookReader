//
//  ReaderOptionsCbzView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/10.
//

import SwiftUI

struct ReaderOptionsCbzView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("About \(ReaderType.ReadiumPDF.rawValue)")
                    .font(.title3).bold()
                Text("""
                        Based on Readium Project.
                        """)
            }.padding()
        }
    }
}

struct ReaderOptionsCbzView_Previews: PreviewProvider {
    static var previews: some View {
        ReaderOptionsCbzView()
    }
}
