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
    
    @State private var presentingReadSheet = false {
        willSet { if newValue { _VM.modelData.presentingStack.append($presentingReadSheet) } }
        didSet { if oldValue { _ = _VM.modelData.presentingStack.popLast() } }
    }
    @State private var alertItem: AlertItem?

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
                            if let types = _VM.modelData.formatReaderMap[_VM.selectedFormat],
                               types.contains(type) {
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            
            Button(action: {
                guard let formatInfo = _VM.listModel.book.formats[_VM.selectedFormat.rawValue],
                      formatInfo.cached else {
                    alertItem = AlertItem(id: "Selected Format Not Cached", msg: "Please download \(_VM.selectedFormat.rawValue) first")
                    return
                }
                readAction(book: _VM.listModel.book, format: _VM.selectedFormat, formatInfo: formatInfo, reader: _VM.selectedFormatReader)
            }) {
                HStack {
                    Spacer()
                    Text("Continue Reading")
                    Spacer()
                }
            }.disabled(_VM.listModel.book.formats[_VM.selectedFormat.rawValue]?.cached != true)
        }
        .navigationTitle(
            Text("\(_VM.position.id) with \(_VM.position.readerName)")
        )
        .fullScreenCover(isPresented: $presentingReadSheet) {
            if let book = _VM.modelData.readingBook, let readerInfo = _VM.modelData.readerInfo {
                YabrEBookReader(book: book, readerInfo: readerInfo)
                    .environmentObject(_VM.modelData)
            } else {
                Text("Nil Book")
            }
        }
        
    }
    
    func readAction(book: CalibreBook, format: Format, formatInfo: FormatInfo, reader: ReaderType) {
        guard let bookFileUrl = getSavedUrl(book: book, format: format)
        else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return
        }
        
       _VM.modelData.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: reader,
            position: _VM.position
        )
    
        _VM.modelData.updatedReadingPosition.update(with: _VM.position)
        
        presentingReadSheet = true
    }

    func updatePosition() {
        _VM.modelData.updateCurrentPosition(alertDelegate: self)
        
        if let book = _VM.modelData.readingBook {
            _VM.listModel.book = book
            _VM.listModel.positions = book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
            if let position = book.readPos.getPosition(_VM.position.id) {
                _VM.position = position
            }
        }
    }
}

extension ReadingPositionDetailView : AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

struct ReadingPositionDetailView_Previews: PreviewProvider {
    @StateObject static var modelData = ModelData(mock: true)

    static var previews: some View {
        let listModel = ReadingPositionListViewModel(modelData: modelData, book: modelData.readingBook!, positions: modelData.readingBook!.readPos.getDevices())
        ReadingPositionDetailView(
            viewModel: ReadingPositionDetailViewModel(
                modelData: modelData,
                listModel: listModel,
                position: modelData.readingBook!.readPos.getDevices().first!
            )
        )
    }
}
