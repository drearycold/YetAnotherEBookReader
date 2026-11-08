import SwiftUI

/// A displayed snapshot, rebuilt on book/download updates rather than querying files in the body.
struct BookFormatState: Identifiable {
    let id: String
    let format: Format?
    let size: UInt64
    let isLocal: Bool
    let fileAvailable: Bool
    let wasCached: Bool
    let download: BookFormatDownload?
    let statusText: String
    let statusIcon: String

    var isTransferring: Bool { download?.isActive == true }
    var canDownload: Bool { !isLocal && format != nil && !isTransferring }
    var canClear: Bool { !isLocal && format != nil && (fileAvailable || wasCached) && !isTransferring }
    var canPreview: Bool { format != nil && fileAvailable && !isTransferring }
    var downloadTitle: String {
        if case .failed = download?.completion { return "Retry \(id) Download" }
        return fileAvailable ? "Download \(id) Again" : "Download \(id) Only"
    }
    var transferText: String {
        if download?.isPausing == true { return "Pausing…" }
        return download?.isDownloading == true ? "Downloading…" : "Paused"
    }
}

struct BookFormatRow: View {
    let state: BookFormatState
    let cache: () -> Void
    let clear: () -> Void
    let preview: () -> Void
    let pauseOrResume: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.id).font(.headline)
                Spacer(minLength: 8)
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: state.size), countStyle: .file))
                    .font(.caption).foregroundColor(.secondary)
            }
            if state.isTransferring, let download = state.download {
                ProgressView(value: download.progress).progressViewStyle(LinearProgressViewStyle())
                Text(state.transferText).font(.subheadline)
            } else {
                Label(state.statusText, systemImage: state.statusIcon)
                    .font(.subheadline).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BookFormatActions(state: state, cache: cache, clear: clear, preview: preview,
                              pauseOrResume: pauseOrResume, cancel: cancel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("book-format.\(state.id)")
    }
}

/// The format row and toolbar offer exactly the same operations and labels.
struct BookFormatActions: View {
    let state: BookFormatState
    let cache: () -> Void
    let clear: () -> Void
    let preview: () -> Void
    let pauseOrResume: () -> Void
    let cancel: () -> Void

    var body: some View {
        Group {
            if state.isTransferring {
                Button(action: pauseOrResume) {
                    Label(state.download?.isDownloading == true ? "Pause \(state.id) Download" : "Resume \(state.id) Download",
                          systemImage: state.download?.isDownloading == true ? "pause" : "play")
                }
                .disabled(state.download?.isPausing == true)
                .frame(minHeight: 44)
                Button(action: cancel) { Label("Cancel \(state.id) Download", systemImage: "xmark") }
                    .frame(minHeight: 44)
            } else {
                if state.canDownload {
                    Button(action: cache) { Label(state.downloadTitle, systemImage: "tray.and.arrow.down") }
                        .frame(minHeight: 44)
                }
                if state.canClear {
                    Button(role: .destructive, action: clear) { Label("Clear \(state.id) Download", systemImage: "trash") }
                        .frame(minHeight: 44)
                }
                if state.canPreview {
                    Button(action: preview) { Label("Preview \(state.id)", systemImage: "doc.text.magnifyingglass") }
                        .frame(minHeight: 44)
                }
            }
        }
        .font(.subheadline)
    }
}
