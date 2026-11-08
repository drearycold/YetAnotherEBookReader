import SwiftUI

struct BookPreviewView: View {
    @ObservedObject var viewModel: BookPreviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Table of Contents").font(.headline)
                        switch viewModel.contentsState {
                        case .loading: ProgressView("Loading table of contents…")
                        case .loaded(let text): Text(text)
                        case .empty: Text("No table of contents in this book.")
                        case .generating:
                            Text("The server is generating the table of contents. Try again shortly.")
                            retry
                        case .failed(let message):
                            Text(message)
                            retry
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .tabItem { Label("Contents", systemImage: "scroll") }.tag(0)
                ZStack {
                    // Keep the tab present even before its reader is mounted.
                    // The reader is mounted only when selected, and is always isolated from reading.
                    if selectedTab == 1 {
                        YabrEBookReader(book: viewModel.book, readerInfo: viewModel.readerInfo, isPreview: true)
                    }
                }
                .tabItem { Label("Preview", systemImage: "book") }.tag(1)
            }
            .navigationTitle("\(viewModel.readerInfo.format.rawValue) Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { viewModel.cancel(); dismiss() }
                        .accessibilityIdentifier("book-preview.close")
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.cancel() }
        .accessibilityIdentifier("screen.book-preview")
    }

    private var retry: some View {
        Button("Retry") { viewModel.loadContents() }
            .frame(minHeight: 44).accessibilityIdentifier("book-preview.retry")
    }
}
