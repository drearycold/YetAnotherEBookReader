import SwiftUI

/// Composition only. The page owns observations, actions and modal/navigation state.
struct BookDetailContentView: View {
    let comments: String
    let commentBaseURL: URL?
    let overview: BookOverviewView
    let progress: BookProgressSection
    let formats: BookFormatList
    let metadata: BookMetadataSection
    let connectivity: BookConnectivitySection
    let countPages: BookCountPagesCorner?

    init(book: CalibreBook, overview: BookOverviewView, progress: BookProgressSection,
         formats: BookFormatList, metadata: BookMetadataSection,
         connectivity: BookConnectivitySection, countPages: BookCountPagesCorner?) {
        comments = book.comments
        commentBaseURL = book.commentBaseURL
        self.overview = overview
        self.progress = progress
        self.formats = formats
        self.metadata = metadata
        self.connectivity = connectivity
        self.countPages = countPages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if canImport(GoogleMobileAds) && GAD_ENABLED
            Banner()
            #endif

            overview
            BookDetailSection("Reading Progress") { progress }
            if !comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               comments != "Without Comments" {
                BookDetailSection("Description") {
                    // Content loading, expansion and height ownership are BD4 work.
                    WebViewUI(content: comments, baseURL: commentBaseURL)
                        .frame(height: 400)
                }
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
