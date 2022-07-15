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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Spacer()
                
                Image(systemName: "laptopcomputer.and.iphone")
                    .frame(minWidth: 32, minHeight: 24)
                VStack(alignment: .leading) {
                    Text("\(_VM.position.id) with \(_VM.position.readerName)")
                    
                    Text("Chapter: \(_VM.position.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines))")
                    
                    HStack {
                        Spacer()
                        Text("\(String(format: "%.2f%% Left", 100 - _VM.position.lastChapterProgress))")
                    }
                    
                    Text("Book: Page \(_VM.position.lastReadPage) / \(_VM.position.maxPage)")
                    
                    HStack {
                        Spacer()
                        Text("\(String(format: "%.2f%% Left", 100 - _VM.position.lastProgress))")
                    }
                    #if DEBUG
                    HStack {
                        Spacer()
                        Text("(\(_VM.position.lastPosition[0]):\(_VM.position.lastPosition[1]):\(_VM.position.lastPosition[2]))")
                    }
                    HStack {
                        Spacer()
                        Text("CFI: \(_VM.position.cfi)")
                    }
                    HStack {
                        Spacer()
                        Text("EPOCH: \(_VM.position.epoch)")
                    }
                    
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
                            if _VM.listModel.book.formats[format.rawValue] != nil {
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
                    guard let formatInfo = _VM.listModel.book.formats[_VM.selectedFormat.rawValue],
                          formatInfo.cached else {
                        alertItem = AlertItem(id: "Selected Format Not Cached", msg: "Please download \(_VM.selectedFormat.rawValue) first")
                        return
                    }
                    readAction(book: _VM.listModel.book, format: _VM.selectedFormat, formatInfo: formatInfo, reader: _VM.selectedFormatReader)
                }) {
                    Text("Start Reading")
                }
                
                Spacer()
            }
            .padding(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
            .disabled(_VM.selectedFormat == Format.UNKNOWN || _VM.selectedFormatReader == ReaderType.UNSUPPORTED)
        }
        .fixedSize(horizontal: true, vertical: false)
        .alert(item: $alertItem) { item in
            if item.id == "ForwardProgress" {
                return Alert(title: Text("Confirm Forward Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    updatePosition()
                }), secondaryButton: .cancel())
            }
            if item.id == "BackwardProgress" {
                return Alert(title: Text("Confirm Backwards Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    updatePosition()
                }), secondaryButton: .cancel())
            }
            if item.id == "ReadingPosition" {
                return Alert(title: Text("Confirm Reading Progress"), message: Text(item.msg ?? ""), primaryButton: .destructive(Text("Confirm"), action: {
                    guard let formatInfo = _VM.listModel.book.formats[_VM.selectedFormat.rawValue] else {
                        return
                    }
                    readAction(book: _VM.listModel.book, format: _VM.selectedFormat, formatInfo: formatInfo, reader: _VM.selectedFormatReader)
                }), secondaryButton: .cancel())
            }
            return Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .fullScreenCover(
            isPresented: $presentingReadSheet,
            onDismiss: {
                guard let book = _VM.modelData.readingBook,
                    let selectedPosition = _VM.modelData.readerInfo?.position,
                      _VM.modelData.updatedReadingPosition.isSameType(with: selectedPosition),
                      _VM.modelData.updatedReadingPosition.isSameProgress(with: selectedPosition) == false else { return }
                
                _VM.modelData.logBookDeviceReadingPositionHistoryFinish(book: book, endPosition: _VM.modelData.updatedReadingPosition)
                
                updatePosition()
                NotificationCenter.default.post(Notification(name: .YABR_RecentShelfBooksRefreshed))
            } ) {
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
            _VM.listModel.positions = book.readPos.getDevices()
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
