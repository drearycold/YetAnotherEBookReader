import SwiftUI

struct BookFormatRow: View {
    let format: Format
    let formatInfo: FormatInfo
    let download: BookFormatDownload?
    let statusText: String
    let statusIcon: String
    let cache: () -> Void
    let clear: () -> Void
    let preview: () -> Void
    let pauseOrResume: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(format.rawValue).font(.headline)
                Spacer(minLength: 8)
                Text(ByteCountFormatter.string(fromByteCount: Int64(formatInfo.serverSize), countStyle: .file))
                    .font(.caption).foregroundColor(.secondary)
            }
            if let download {
                ProgressView(value: download.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                HStack {
                    Text(download.isDownloading ? "Downloading…" : "Paused")
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    formatButton(download.isDownloading ? "pause" : "play",
                                 label: download.isDownloading ? "Pause Download" : "Resume Download", action: pauseOrResume)
                    formatButton("xmark", label: "Cancel Download", action: cancel)
                }
            } else {
                Label(statusText, systemImage: statusIcon)
                    .font(.subheadline).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                formatButton("tray.and.arrow.down", label: "Download \(format.rawValue) Only", action: cache)
                    .disabled(download != nil)
                formatButton("tray.and.arrow.up", label: "Clear \(format.rawValue) Download", action: clear)
                    .disabled(!formatInfo.cached)
                formatButton("doc.text.magnifyingglass", label: "Preview \(format.rawValue)", action: preview)
                    .disabled(!formatInfo.cached)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func formatButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text(label))
    }
}
