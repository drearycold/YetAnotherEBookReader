//
//  ReadingPositionView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/23.
//

import SwiftUI

struct ReadingPositionListView: View {
    @ObservedObject private var _positionViewModel: ReadingPositionListViewModel

    init(viewModel: ReadingPositionListViewModel) {
        self._positionViewModel = viewModel
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                List {
                    ForEach(_positionViewModel.book.readPos.getDevices(), id: \.id) { position in
                        NavigationLink(
                            destination: ReadingPositionDetailView(
                                viewModel: ReadingPositionDetailViewModel(
                                    modelData: _positionViewModel.modelData,
                                    book: _positionViewModel.book,
                                    position: position)
                            )
                        ) {
                            VStack(alignment: .leading) {
                                Text("\(position.id)")
                                Text("\(String(format: "%.2f%%", position.lastProgress)), with \((_positionViewModel.modelData.formatOfReader(readerName: position.readerName) ?? Format.UNKNOWN).rawValue) by \(position.readerName)")
                                if position.id == _positionViewModel.modelData.deviceName {
                                    Text("(Current Device)")
                                        .font(.caption)
                                        .foregroundColor(Color(UIColor.systemRed))
                                }
                            }
                            
                        }
                        
                        
                    }
                    .onDelete(perform: { indexSet in
                        let deviceNames = indexSet.reduce(into: [String]()) { result, index in
                            result.append(_positionViewModel.book.readPos.getDevices()[index].id)
                        }
                        
                        deviceNames.forEach { deviceName in
                            _positionViewModel.removePosition(deviceName)
                        }
                    })
                    
                    if _positionViewModel.book.readPos.getPosition(_positionViewModel.modelData.deviceName) == nil {
                        ForEach(_positionViewModel.book.formats.sorted {
                            $0.key < $1.key
                        }.compactMap {
                            if let format = Format(rawValue: $0.key),
                               let reader = _positionViewModel.modelData.formatReaderMap[format]?.first {
                                return (format, reader, $0.value)
                            } else {
                                return nil
                            }
                        } as [(Format, ReaderType, FormatInfo)], id: \.0) { format, reader, formatInfo in
                            NavigationLink(
                                destination: ReadingPositionDetailView(
                                    viewModel: ReadingPositionDetailViewModel(
                                        modelData: _positionViewModel.modelData,
                                        book: _positionViewModel.book,
                                        position: _positionViewModel.modelData.getInitialReadingPosition(book: _positionViewModel.book, format: format, reader: reader))
                                )
                            ) {
                                VStack(alignment: .leading) {
                                    Text("Start from Beginning")
                                    Text("with \(format.rawValue) by \(reader.rawValue)")
                                }
                                
                            }
                        }
                    }
                }
            }
            .navigationTitle("Progress by Device")
            .navigationBarTitleDisplayMode(.inline)
            .statusBar(hidden: true)
        }
        .navigationViewStyle(DefaultNavigationViewStyle())
        .listStyle(PlainListStyle())
        .onDisappear() {
            guard _positionViewModel.modified else { return }
            _positionViewModel.modelData.updateBook(book: _positionViewModel.book)
        }
    }
}

struct ReadingPositionView_Previews: PreviewProvider {
    @StateObject static var modelData = ModelData(mock: true)
    static var previews: some View {
        ReadingPositionListView(viewModel: ReadingPositionListViewModel(
            modelData: modelData,
            book: modelData.readingBook!
        ))
            
    }
}
