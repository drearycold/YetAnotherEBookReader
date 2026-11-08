import SwiftUI

/// Composition only. The page owns observations, actions and modal/navigation state.
struct BookDetailContentView: View {
    let description: BookDescriptionDocument
    let overview: BookOverviewView
    let progress: BookProgressSection
    let formats: BookFormatList
    let metadata: BookMetadataSection
    let connectivity: BookConnectivitySection
    let countPages: BookCountPagesCorner?
    let scrollToDescription: () -> Void

    init(book: CalibreBook, overview: BookOverviewView, progress: BookProgressSection,
         formats: BookFormatList, metadata: BookMetadataSection,
         connectivity: BookConnectivitySection, countPages: BookCountPagesCorner?,
         scrollToDescription: @escaping () -> Void = {}) {
        description = BookDescriptionDocument(html: book.comments, baseURL: book.commentBaseURL)
        self.overview = overview
        self.progress = progress
        self.formats = formats
        self.metadata = metadata
        self.connectivity = connectivity
        self.countPages = countPages
        self.scrollToDescription = scrollToDescription
    }

    static let descriptionID = "book-detail.description"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if canImport(GoogleMobileAds) && GAD_ENABLED
            Banner()
            #endif

            overview
            BookDetailSection("Reading Progress") { progress }
            if description.hasMarkup {
                BookDescriptionSection(document: description, scrollToHeading: scrollToDescription)
                    .id(Self.descriptionID)
            }
            BookDetailSection("Files and Formats") { formats }
            BookDetailSection("Book Information") { metadata }
            if let countPages {
                BookDetailSection("Count Pages") { countPages }
            }
            BookDetailSection("Sync and Advanced") { connectivity }

            #if canImport(GoogleMobileAds) && GAD_ENABLED
            Banner()
            #endif
        }
    }
}

struct BookDetailSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
