//
//  BookFormatRow.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookFormatRow: View {
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var format: Format
    var formatInfo: FormatInfo
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            metadataFormatIcon(format.rawValue)
                .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .bottom, spacing: 24) {
                    Text(format.rawValue)
                        .font(.subheadline)
                        .frame(minWidth: 48, alignment: .leading)
                    
                    cacheFormatButton
                        .disabled(viewModel.isFormatDownloading(bookId: book.id, format: format))
                    
                    clearFormatButton
                        .disabled(!formatInfo.cached)
                    
                    previewFormatButton
                        .disabled(!formatInfo.cached)
                }
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(formatInfo.serverSize), countStyle: .file))
                    if let download = viewModel.getActiveDownload(bookId: book.id, format: format) {
                        ProgressView(value: download.progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(maxWidth: 160)
                        
                        Button(action: {
                            if download.isDownloading {
                                viewModel.pauseDownload(book: book, format: format)
                            } else {
                                viewModel.resumeDownload(book: book, format: format)
                            }
                        }) {
                            Image(systemName: download.isDownloading ? "pause" : "play")
                        }
                        
                        Button(action:{
                            viewModel.cancelDownload(book: book, format: format)
                        }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.red)
                        }
                    } else if formatInfo.cached {
                        Text(viewModel.getFormatStatusText(formatInfo: formatInfo))
                        Image(systemName: viewModel.getFormatStatusIcon(formatInfo: formatInfo))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Not cached")
                    }
                }
                .font(.caption)
            }
        }
    }
    
    private var cacheFormatButton: some View {
        Button(action:{
            viewModel.cacheFormat(book: book, format: format)
        }) {
            Image(systemName: "tray.and.arrow.down")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    private var clearFormatButton: some View {
        Button(action:{
            viewModel.clearFormat(book: book, format: format)
        }) {
            Image(systemName: "tray.and.arrow.up")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    private var previewFormatButton: some View {
        Button(action: {
            if viewModel.previewAction(book: book, format: format, formatInfo: formatInfo) {
                viewModel.presentingPreviewSheet = true
            }
        }) {
            Image(systemName: "doc.text.magnifyingglass")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
    }
    
    private func metadataFormatIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
    }
}
