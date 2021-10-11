//
//  FormatOptionsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/10/10.
//

import SwiftUI

struct FormatOptionsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Determines which format to download")
                    .font(.title3)
                    .bold()
                Text("If there exist multiple file formats for a single book, this option will help determine which format will get download to device when book is being added to shelf through \(Image(systemName: "star")).")
                Text("Each format can be managed from book info page:")
                Text("""
                        \(Image(systemName: "tray.and.arrow.down")): Download
                        \(Image(systemName: "tray.and.arrow.up")): Remove
                        \(Image(systemName: "doc.text.magnifyingglass")) : TOC and Preview
                    """)
                Text("")
                    .font(.caption)
                Text("Determines which format to open")
                    .font(.title3).bold()
                Text("Normally, book reading will continue from last used format and reading position. Only when where is no previous reading position and multiple file formats have been downloaded, this option will help determine which format will get open.")
                Text("")
                Text("Fallback to other format")
                    .font(.title3).bold()
                Text("If the book specified does not contain the preferred format, we will try in sequence: \(Format.EPUB.rawValue) -> \(Format.PDF.rawValue) -> \(Format.CBZ.rawValue).")
            }.padding()
        }
    }
}

struct FormatOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        FormatOptionsView()
    }
}
