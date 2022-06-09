//
//  ReadingPositionHistoryDetailView.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/6/8.
//

import SwiftUI

struct ReadingPositionHistoryDetailView: View {
    @EnvironmentObject var modelData: ModelData

    let positionHistory: BookDeviceReadingPositionHistoryRealm
    
    @State private var overrideToggle = false
    @State private var selectedFormat = Format.UNKNOWN
    @State private var selectedFormatReader = ReaderType.UNSUPPORTED
    
    @State private var presentingReadSheet = false {
        willSet { if newValue { modelData.presentingStack.append($presentingReadSheet) } }
        didSet { if oldValue { _ = modelData.presentingStack.popLast() } }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let libraryId = positionHistory.libraryId,
                   let library = modelData.calibreLibraries[libraryId] {
                    if let book = modelData.queryBookRealm(book: CalibreBook(id: positionHistory.bookId, library: library), realm: modelData.realm) {
                        Text("Book Title:").frame(minWidth: 100, alignment: .leading)
                        Text(book.title)
                    } else {
                        Text("Library Name:").frame(minWidth: 100, alignment: .leading)
                        Text(library.name)
                    }
                } else {
                    Text("Device:").frame(minWidth: 100, alignment: .leading)
                    Text(modelData.deviceName)
                }
                Spacer()
            }.font(.title2)
            
            HStack {
                Text("Start Datetime:")
                Text(positionHistory.startDatetime.description(with: Locale.autoupdatingCurrent))
            }
                
            if let position = positionHistory.endPosition {
                VStack(alignment: .leading) {
                    Text("Updated Position")
                        .font(.title3)
                    positionDetailView(position: position)
                        .navigationTitle("\(position.lastReadChapter), \(String(format: "%.0f%%", position.lastChapterProgress)) / \(String(format: "%.0f%%", position.lastProgress))")
                        .onAppear {
                            if let format = modelData.formatOfReader(readerName: position.readerName) {
                                selectedFormat = format
                                updateSelectedFormatReader(position: position)
                            } else {
                                selectedFormat = Format.UNKNOWN
                            }
                        }
                }
                
                if let libraryId = positionHistory.libraryId,
                   let library = modelData.calibreLibraries[libraryId],
                   let book = modelData.queryBookRealm(book: CalibreBook(id: positionHistory.bookId, library: library), realm: modelData.realm) {
                    VStack {
                        Toggle("Override Format/Reader", isOn: $overrideToggle)
                        
                        HStack {
                            Text("Format")
                                .font(.subheadline)
                                .frame(minWidth: 40, alignment: .trailing)
                            Picker("Format", selection: $selectedFormat) {
                                ForEach(Format.allCases) { format in
                                    if let formatInfo = book.formats()[format.rawValue], formatInfo.cached {
                                        Text(format.rawValue).tag(format)
                                    }
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .onChange(of: selectedFormat) { _ in
                                updateSelectedFormatReader(position: position)
                            }
                        }.disabled(!overrideToggle)
                        
                        HStack {
                            Text("Reader")
                                .font(.subheadline)
                                .frame(minWidth: 40, alignment: .trailing)
                            Picker("Reader", selection: $selectedFormatReader) {
                                ForEach(ReaderType.allCases) { type in
                                    if let types = modelData.formatReaderMap[selectedFormat],
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
                            readAction(bookRealm: book, format: selectedFormat, reader: selectedFormatReader, positionRealm: position)
                        }) {
                            Text("Start Reading")
                        }
                        .fullScreenCover(
                            isPresented: $presentingReadSheet,
                            onDismiss: {
                                guard let book = modelData.readingBook,
                                    let selectedPosition = modelData.readerInfo?.position,
                                      modelData.updatedReadingPosition.isSameProgress(with: selectedPosition) == false else { return }
                                
                                modelData.logBookDeviceReadingPositionHistoryFinish(book: book, endPosition: modelData.updatedReadingPosition)
                                
                                modelData.updateCurrentPosition(alertDelegate: nil)
                                
                                NotificationCenter.default.post(Notification(name: .YABR_BooksRefreshed))
                            }
                        ) {
                            if let book = modelData.readingBook, let readerInfo = modelData.readerInfo {
                                YabrEBookReader(book: book, readerInfo: readerInfo)
                                    .environmentObject(modelData)
                            } else {
                                Text("Nil Book")
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
                    .disabled(selectedFormat == Format.UNKNOWN || selectedFormatReader == ReaderType.UNSUPPORTED)
                }
            }
            
            if let position = positionHistory.startPosition {
                VStack(alignment: .leading) {
                    Text("Previous Position")
                        .font(.title3)
                    positionDetailView(position: position)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func updateSelectedFormatReader(position: BookDeviceReadingPositionRealm) {
        if selectedFormat == Format.UNKNOWN {
            return
        }
        print("selectedFormat \(selectedFormat.rawValue)")
        
        guard let readers = modelData.formatReaderMap[selectedFormat] else { return }
        selectedFormatReader = readers.reduce(into: readers.first!) {
            if $1.rawValue == position.readerName {
                $0 = $1
            }
        }
    }
    
    func readAction(bookRealm: CalibreBookRealm, format: Format, reader: ReaderType, positionRealm: BookDeviceReadingPositionRealm) {
        guard let book = modelData.convert(bookRealm: bookRealm),
              let bookFileUrl = getSavedUrl(book: book, format: format) else { return }
        
        let readingPosition = BookDeviceReadingPosition(managedObject: positionRealm)
        
        modelData.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: reader,
            position: readingPosition
        )
    
        modelData.updatedReadingPosition.update(with: readingPosition)
        
        presentingReadSheet = true
    }

    @ViewBuilder
    private func positionDetailView(position: BookDeviceReadingPositionRealm) -> some View {
        HStack(alignment: .top) {
            Spacer()
            
            Image(systemName: "laptopcomputer.and.iphone")
                .frame(minWidth: 32, minHeight: 24)
            VStack(alignment: .leading) {
                Text("\(position.id) with \(position.readerName)")
                
                Text("Chapter: \(position.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines))")
                
                HStack {
                    Text("Chapter Progress:")
                    Text("\(String(format: "%.2f%%", position.lastChapterProgress))")
                }
                
                HStack {
                    Text("Book:")
                    if modelData.formatOfReader(readerName: position.readerName) == .EPUB {
                        Text("HTML No. \(position.lastReadPage)")
                    } else {
                        Text("Page \(position.lastReadPage) / \(position.maxPage)")
                    }
                }
                
                HStack {
                    Text("Book Progress:")
                    Text("\(String(format: "%.2f%%", position.lastProgress))")
                }
                
                HStack {
                    Text("Datetime:")
                    Text(position.epochLocaleLong)
                }
                
                HStack {
                    Text("Epoch:")
                    Text(position.epoch.description)
                }
                #if DEBUG
                HStack {
                    Spacer()
                    Text("(\(position.lastPosition[0]):\(position.lastPosition[1]):\(position.lastPosition[2]))")
                }
                #endif
            }
            
            Spacer()
        }
    }
}

struct ReadingPositionHistoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        ReadingPositionHistoryDetailView(positionHistory: BookDeviceReadingPositionHistoryRealm())
    }
}
