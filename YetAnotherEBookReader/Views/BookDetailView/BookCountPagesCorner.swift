//
//  BookCountPagesCorner.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookCountPagesCorner: View {
    var book: CalibreBook
    var lastUpdated: Date
    var countPage: CalibreCountPagesPrefs.LibraryConfig
    var isCompat: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Count Pages Info Corner")
            HStack {
                Text("Pages \(book.userMetadataNumberAsIntDescription(column: countPage.pageCountCN) ?? "not set")")
                Text("/").padding([.leading, .trailing], 16)
                Text("Words \(book.userMetadataNumberAsIntDescription(column: countPage.wordCountCN) ?? "not set")")
            }.font(.subheadline)
            HStack {
                Text("Readability \(book.userMetadataNumberAsFloatDescription(column: countPage.fleschReadingEaseCN) ?? "not set") / \(book.userMetadataNumberAsFloatDescription(column: countPage.fleschKincaidGradeCN) ?? "not set") / \(book.userMetadataNumberAsFloatDescription(column: countPage.gunningFogIndexCN) ?? "not set")")
            }.font(.subheadline)
        }
    }
}
