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
    
    @State private var presentingReadSheet = false
    @State private var alertItem: AlertItem?

    init(viewModel: ReadingPositionDetailViewModel) {
        self._VM = viewModel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Spacer()
                
                Image(systemName: "laptopcomputer.and.iphone")
                    .frame(minWidth: 32, minHeight: 24)
                VStack(alignment: .leading) {
                    Text("\(_VM.position.id) with \(_VM.position.readerName)")
                    Text("Chapter: \(_VM.position.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines)), \(String(format: "%.2f%% Left", 100 - _VM.position.lastChapterProgress))")
                    Text("Book: Page \(_VM.position.lastReadPage) / \(_VM.position.maxPage), \(String(format: "%.2f%% Left", 100 - _VM.position.lastProgress))")
                    #if DEBUG
                    Text("(\(_VM.position.lastPosition[0]):\(_VM.position.lastPosition[1]):\(_VM.position.lastPosition[2]))")
                    #endif
                }
                
                Spacer()
            }.coordinateSpace(name: CoordinateSpace.named("INFO"))
            
            VStack {
                Toggle("Override Format/Reader", isOn: $overrideToggle)
                
                HStack {
                    Text("Format")
                        .font(.subheadline)
                        .frame(minWidth: 40, alignment: .trailing)
                    Picker("Format", selection: $_VM.selectedFormat) {
                        ForEach(Format.allCases) { format in
                            if _VM.book.formats[format.rawValue] != nil {
                                Text(format.rawValue).tag(format)
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: _VM.selectedFormat) { newFormat in
                        if newFormat == Format.UNKNOWN {
                            return
                        }
                        print("selectedFormat \(newFormat.rawValue)")
                        
                        guard let readers = _VM.modelData.formatReaderMap[newFormat] else { return }
                        _VM.selectedFormatReader = readers.reduce(into: readers.first!) {
                            if $1.rawValue == _VM.position.readerName {
                                $0 = $1
                            }
                        }
                    }
                }.disabled(!overrideToggle)
                
                HStack {
                    Text("Reader")
                        .font(.subheadline)
                        .frame(minWidth: 40, alignment: .trailing)
                    Picker("Reader", selection: $_VM.selectedFormatReader) {
                        ForEach(ReaderType.allCases) { type in
                            if let types = _VM.modelData.formatReaderMap[_VM.selectedFormat],
                               types.contains(type) {
                                Text(type.rawValue).tag(type)
                            }
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }.disabled(!overrideToggle)
                
//                HStack {
//                    Text("Start Page")
//                    TextField("Start Page", text: $_VM.startPage)
//                }
                
            }.padding(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            
            HStack {
                Spacer()
                
                Button(action: {
                    guard let formatInfo = _VM.book.formats[_VM.selectedFormat.rawValue] else {
                        return
                    }
                    readAction(book: _VM.book, format: _VM.selectedFormat, formatInfo: formatInfo, reader: _VM.selectedFormatReader)
                }) {
                    Text("Continue Reading")
                }
                
                Spacer()
            }
            .padding(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
            .disabled(_VM.selectedFormat == Format.UNKNOWN || _VM.selectedFormatReader == ReaderType.UNSUPPORTED)
        }
        .fixedSize(horizontal: true, vertical: false)
        .fullScreenCover(isPresented: $presentingReadSheet, onDismiss: {presentingReadSheet = false} ) {
            if let readerInfo = _VM.modelData.readerInfo {
                YabrEBookReader(readerInfo: readerInfo)
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

}

struct ReadingPositionDetailView_Previews: PreviewProvider {
    @StateObject static var modelData = ModelData(mock: true)

    static var previews: some View {
        ReadingPositionDetailView(
            viewModel: ReadingPositionDetailViewModel(
                modelData: modelData,
                book: modelData.readingBook!,
                position: modelData.readingBook!.readPos.getDevices().first!
            )
        )
    }
}
