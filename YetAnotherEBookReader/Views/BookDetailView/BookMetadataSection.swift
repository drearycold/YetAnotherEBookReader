import SwiftUI

struct BookMetadataSection: View {
    // CalibreBook equality is identity-only. Store displayed fields so SwiftUI sees edits.
    let rating: String?
    let publisher: String?
    let publicationDate: String?
    let series: String?
    let tags: String?
    let goodreadsRating: String?
    let goodreadsShelves: [String]?
    let goodreadsURL: URL?
    let amazonURL: URL?

    init(book: CalibreBook, goodreadsRating: String?, goodreadsShelves: [String]?) {
        rating = book.rating > 0 ? book.ratingDescription : nil
        publisher = book.publisher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || book.publisher == "Unknown" ? nil : book.publisher
        // Calibre's undefined year is Gregorian, independent of the user's preferred calendar.
        // Keep the existing localized formatter for valid dates; imports also use the epoch.
        let publicationYear = Calendar(identifier: .gregorian).component(.year, from: book.pubDate)
        publicationDate = book.pubDate.timeIntervalSince1970 != 0 && publicationYear > 101
            ? book.pubDateByLocale : nil
        series = book.series.isEmpty ? nil : "\(book.series) (\(book.seriesIndexDescription))"
        tags = book.tags.isEmpty ? nil : book.tagsDescription
        self.goodreadsRating = goodreadsRating
        self.goodreadsShelves = goodreadsShelves
        goodreadsURL = Self.externalURL(service: "goodreads", book: book)
        amazonURL = Self.externalURL(service: "amazon", book: book)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rating { BookMetadataValue(title: "Rating", value: rating) }
            if let goodreadsRating { BookMetadataValue(title: "Goodreads Rating", value: goodreadsRating) }
            if let publisher { BookMetadataValue(title: "Publisher", value: publisher) }
            if let publicationDate { BookMetadataValue(title: "Published", value: publicationDate) }
            if let series { BookMetadataValue(title: "Series", value: series) }
            if let tags { BookMetadataValue(title: "Tags", value: tags) }
            if let goodreadsShelves { BookMetadataValue(title: "Goodreads Shelves", value: goodreadsShelves.joined(separator: ", ")) }
            VStack(alignment: .leading, spacing: 4) {
                Text("External Links").font(.subheadline).foregroundColor(.secondary)
                if let url = goodreadsURL {
                    Link(destination: url) { Label("Goodreads", systemImage: "arrow.up.right.square") }
                        .frame(minHeight: 44)
                }
                if let url = amazonURL {
                    Link(destination: url) { Label("Amazon", systemImage: "arrow.up.right.square") }
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private static func externalURL(service: String, book: CalibreBook) -> URL? {
        if let identifier = book.identifiers[service], !identifier.isEmpty {
            let base = service == "goodreads" ? "https://www.goodreads.com/book/show" : "https://www.amazon.com/dp"
            return URL(string: base)?.appendingPathComponent(identifier)
        }
        var components = URLComponents(string: service == "goodreads" ? "https://www.goodreads.com/search" : "https://www.amazon.com/s")
        components?.queryItems = [URLQueryItem(name: service == "goodreads" ? "q" : "k", value: book.title + " " + book.authors.joined(separator: " "))]
        return components?.url
    }
}

struct BookMetadataValue: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundColor(.secondary)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
