import Foundation
import ReadiumShared
import ReadiumStreamer

struct LocalPublicationMetadata: Sendable {
    let title: String?
    let cover: Data?

    @Sendable
    static func load(_ url: URL) async throws -> Self {
        try Task.checkCancellation()
        let client = DefaultHTTPClient()
        let retriever = AssetRetriever(httpClient: client)
        guard let absoluteURL = url.anyURL.absoluteURL else { throw URLError(.badURL) }
        let asset = try await retriever.retrieve(url: absoluteURL).get()
        try Task.checkCancellation()
        let opener = PublicationOpener(parser: DefaultPublicationParser(
            httpClient: client, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()))
        let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
        try Task.checkCancellation()
        let cover = try? await publication.coverFitting(maxSize: CGSize(width: 300, height: 400)).get()
        try Task.checkCancellation()
        return Self(title: publication.metadata.title, cover: cover?.pngData())
    }
}
