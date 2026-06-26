//
//  BookFormatList.swift
//  YetAnotherEBookReader
//

import SwiftUI

struct BookFormatList: View {
    @ObservedObject var viewModel: BookDetailViewModel
    var book: CalibreBook
    var lastUpdated: Date
    var isCompat: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(book.formats.sorted {
                $0.key < $1.key
            }.compactMap {
                if let format = Format(rawValue: $0.key) {
                    return (format, $0.value)
                }
                return nil
            } as [(Format, FormatInfo)], id: \.0) { format, formatInfo in
                BookFormatRow(viewModel: viewModel, book: book, format: format, formatInfo: formatInfo)
            }
        }
        .sheet(isPresented: $viewModel.presentingPreviewSheet, onDismiss: {
            viewModel.handlePreviewDismiss(book: book)
        }) {
            BookPreviewView(viewModel: viewModel.previewViewModel)
        }
    }
}
