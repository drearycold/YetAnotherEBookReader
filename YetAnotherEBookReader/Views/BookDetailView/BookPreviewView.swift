//
//  BookPreviewView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/29.
//

import SwiftUI

struct BookPreviewView: View {
    @ObservedObject private var _VM: BookPreviewViewModel
    
    init(viewModel: BookPreviewViewModel) {
        self._VM = viewModel
    }
    
    var body: some View {
        TabView {
            ScrollView(.vertical) {
                VStack(alignment: .leading) {
                    Text("Table of Content")
                        .font(.headline)
                    Text(_VM.toc)
                }.padding()
            }
            .tabItem {
                Image(systemName: "scroll")
                Text("Manifest")
            }.tag(0)
            
            VStack {
                YabrEBookReader(
                    book: _VM.book,
                    readerInfo: ReaderInfo(
                        deviceName: _VM.modelData.deviceName,
                        url: _VM.url,
                        missing: false,
                        format: _VM.format,
                        readerType: _VM.reader,
                        position: _VM.book.readPos.createInitial(deviceName: _VM.modelData.deviceName, reader: _VM.reader)                        
                    )
                )
            }
            .tabItem {
                Image(systemName: "book")
                Text("Preview")
            }.tag(1)
        }
    }
    
    
}

struct BookPreviewView_Previews: PreviewProvider {
    @StateObject static var modelData = ModelData(mock: true)

    static var previews: some View {
        BookPreviewView(
            viewModel: BookPreviewViewModel(
                modelData: modelData,
                book: modelData.readingBook!,
                url: getSavedUrl(
                    book: modelData.readingBook!,
                    format: modelData.defaultReaderForDefaultFormat(
                        book: modelData.readingBook!
                    ).0)!,
                format: modelData.defaultReaderForDefaultFormat(book: modelData.readingBook!).0,
                reader: modelData.defaultReaderForDefaultFormat(book: modelData.readingBook!).1
            )
        )
    }
}
