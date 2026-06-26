//
//  ReadingPositionDetailView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/25.
//

import SwiftUI

struct ReadingPositionDetailView: View {
    @ObservedObject private var _VM: ReadingPositionDetailViewModel
    
    @State private var overrideToggle = false
    
    init(viewModel: ReadingPositionDetailViewModel) {
        self._VM = viewModel
    }
    
    var body: some View {
        List {
            Section(header: Text("Last Position") ) {
                if _VM.position.structuralStyle == 1, _VM.position.lastReadBook.isEmpty == false {
                    HStack {
                        Text("Book")
                        Spacer()
                        Text(_VM.position.lastReadBook)
                    }
                }
                HStack {
                    Text("Section")
                    Spacer()
                    Text("\(_VM.position.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                HStack {
                    Text("Progress")
                    Spacer()
                    Text(_VM.percentFormatter.string(from: NSNumber(value: _VM.position.lastChapterProgress / 100)) ?? "")
                    Text("/")
                    Text(_VM.percentFormatter.string(from: NSNumber(value: _VM.position.lastProgress / 100)) ?? "")
                }
                HStack {
                    Text("Time")
                    Spacer()
                    Text(_VM.dateFormatter.string(from: Date(timeIntervalSince1970: _VM.position.epoch)))
                }
            }

#if DEBUG
            Section(header: Text("Debug")) {
                HStack {
                    Text("Entry")
                    Spacer()
                    Text("\(_VM.position.lastReadPage) / \(_VM.position.maxPage)")
                }
                HStack {
                    Text("Position")
                    Spacer()
                    Text("(\(_VM.position.lastPosition[0]):\(_VM.position.lastPosition[1]):\(_VM.position.lastPosition[2]))")
                }
                HStack {
                    Text("CFI")
                    Spacer()
                    Text(_VM.position.cfi.replacingOccurrences(of: ";", with: ";\n")).lineLimit(10)
                }
                HStack {
                    Text("Epoch")
                    Spacer()
                    Text(_VM.position.epoch.description)
                }
                if _VM.position.structuralStyle == 1, _VM.position.lastReadBook.isEmpty == false {
                    HStack {
                        Text("Bundle Progress")
                        Spacer()
                        Text(_VM.percentFormatter.string(from: NSNumber(value: _VM.position.lastBundleProgress / 100)) ?? "")
                    }
                }
            }
#endif
            
            Section(header: Text("Override Reader")) {
                HStack {
                    Picker("Reader", selection: $_VM.selectedFormatReader) {
                        ForEach(ReaderType.allCases) { type in
                            if _VM.availableReaders.contains(type) {
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            Button(action: {
                _VM.readSelectedFormat()
            }) {
                HStack {
                    Spacer()
                    Text("Continue Reading")
                    Spacer()
                }
            }.disabled(!_VM.isSelectedFormatCached)
        }
        .navigationTitle(
            Text("\(_VM.position.id) with \(_VM.position.readerName)")
        )
        .fullScreenCover(isPresented: $_VM.presentingReadSheet) {
            if let book = _VM.readingBook, let readerInfo = _VM.readerInfo {
                YabrEBookReader(book: book, readerInfo: readerInfo)
                    .environmentObject(_VM.modelData)
            } else {
                Text("Nil Book")
            }
        }
        .alert(item: $_VM.alertItem) { item in
            Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
    }
}

struct ReadingPositionDetailView_Previews: PreviewProvider {
    @StateObject static var modelData = ModelData(mock: true)

    static var previews: some View {
        let listModel = ReadingPositionListViewModel(modelData: modelData, book: modelData.readingBook!, positions: modelData.readingPositionRepository.getPositions(forBookId: modelData.readingBook!.bookPrefId))
        ReadingPositionDetailView(
            viewModel: ReadingPositionDetailViewModel(
                modelData: modelData,
                listModel: listModel,
                position: modelData.readingPositionRepository.getPositions(forBookId: modelData.readingBook!.bookPrefId).first!
            )
        )
    }
}
