import SwiftUI

struct BookCountPagesCorner: View {
    let pages: String
    let words: String
    let readability: String

    init(book: CalibreBook, countPage: CalibreCountPagesPrefs.LibraryConfig) {
        pages = book.userMetadataNumberAsIntDescription(column: countPage.pageCountCN) ?? "not set"
        words = book.userMetadataNumberAsIntDescription(column: countPage.wordCountCN) ?? "not set"
        readability = "\(book.userMetadataNumberAsFloatDescription(column: countPage.fleschReadingEaseCN) ?? "not set") / \(book.userMetadataNumberAsFloatDescription(column: countPage.fleschKincaidGradeCN) ?? "not set") / \(book.userMetadataNumberAsFloatDescription(column: countPage.gunningFogIndexCN) ?? "not set")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BookMetadataValue(title: "Pages", value: pages)
            BookMetadataValue(title: "Words", value: words)
            BookMetadataValue(title: "Readability", value: readability)
        }
    }
}
