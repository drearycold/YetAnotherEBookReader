//
//  ReadingPositionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/2.
//

import SwiftUI
import SwiftUICharts

struct ReadingPositionHistoryView: View {
    @EnvironmentObject var modelData: ModelData
        
    let libraryId: String?
    let bookId: Int32?
    
    //model
    @State private var readingStatistics = [Double]()
    @State private var maxMinutes = 0
    @State private var avgMinutes = 0
    @State private var _positionViewModel: ReadingPositionListViewModel? = nil
    
    var body: some View {
        VStack {
            BarChartView(data: ChartData(points: readingStatistics), title: "Weekly Read Time", legend: "Minutes", form: ChartForm.large, valueSpecifier: "%.1f")
                .padding()
            
            List {
//                Section(
//                    header: Text("Stats"),
//                    footer: HStack {
//                        Spacer()
//                        Text("Of Last 7 Days: Max \(maxMinutes), Mean \(avgMinutes) (Min./Day)")
//                    }
//                ) {
//                    BarChartView(data: ChartData(points: readingStatistics), title: "Weekly Read Time", legend: "Minutes", form: ChartForm.large, valueSpecifier: "%.1f")
//                }
                
                if let viewModel = _positionViewModel {
                    if viewModel.positions.isEmpty == false {
                        ForEach(viewModel.positionsDeviceKeys(), id: \.self) { deviceId in
                            Section(
                                header: HStack {
                                    Text("On \(deviceId)")
                                    Spacer()
                                    if deviceId == modelData.deviceName {
                                        Text("This Device").foregroundColor(.red)
                                    }
                                }
                            ) {
                                ForEach(viewModel.positionsByLatestStyle(deviceId: deviceId), id: \.hashValue) { position in
                                    NavigationLink(
                                        destination: ReadingPositionDetailView(
                                            viewModel: ReadingPositionDetailViewModel(
                                                modelData: modelData,
                                                listModel: _positionViewModel!,
                                                position: position)
                                        )
                                    ) {
                                        row(position: position)
                                    }
                                }
                            }
                        }
                    } else {
                        #if debug
                        Button(action: {
                            
                        } ) {
                            Text("Start Reading Now")
                            
                        }
                        Text(getSavedUrl(book: viewModel.book, format: Format.EPUB)?.absoluteString ?? "NO URL")
                        Text(getBookBaseUrl(id: viewModel.book.id, library: viewModel.book.library, localFilename: viewModel.book.formats.first?.value.filename)?.absoluteString ?? "NIL")
                        #endif
                    }
                } else {
                    Text("Missing View Model")
                }
                
    //            Section(header: Text("Local Activities")) {
    //                ForEach(modelData.listBookDeviceReadingPositionHistory(bookId: bookId, libraryId: libraryId), id: \.self) { obj in
    //                    NavigationLink(
    //                        destination: ReadingPositionHistoryDetailView(
    //                            positionHistory: obj
    //                        ).environmentObject(modelData)
    //                    ) {
    //                        row(obj: obj)
    //                    }
    //                }
    //            }
                
                Section(header: Text("Local Activities")) {
                    ForEach(modelData.listBookDeviceReadingPositionHistory(bookId: bookId, libraryId: libraryId), id: \.self) { obj in
                        NavigationLink(
                            destination: ReadingPositionDetailView(
                                viewModel: ReadingPositionDetailViewModel(
                                    modelData: modelData,
                                    listModel: _positionViewModel!,
                                    position: BookDeviceReadingPosition(managedObject: obj.endPosition!))
                            )
                        ) {
                            row(position: BookDeviceReadingPosition(managedObject: obj.endPosition!))
                        }
                    }
                }
            }
        }
        
        .onAppear {
            readingStatistics = modelData.getReadingStatistics(bookId: bookId, libraryId: libraryId)
            maxMinutes = Int(readingStatistics.dropLast().max() ?? 0)
            avgMinutes = Int(readingStatistics.dropLast().reduce(0.0,+) / Double(readingStatistics.count - 1))
            if let libraryId = libraryId, let bookId = bookId,
                let library = modelData.calibreLibraries[libraryId] {
                
                if let bookRealm = modelData.queryBookRealm(book: CalibreBook(id: bookId, library: library), realm: modelData.realm),
                    let book = modelData.convert(bookRealm: bookRealm) {
                    _positionViewModel = ReadingPositionListViewModel(modelData: modelData, book: book, positions: book.readPos.getDevices())
                } else if let book = modelData.readingBook {
                    _positionViewModel = ReadingPositionListViewModel(modelData: modelData, book: book, positions: book.readPos.getDevices())
                }
            }
            
            
        }
        .navigationTitle("Reading History")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func row(position: BookDeviceReadingPosition) -> some View {
        VStack(alignment: .leading) {
            HStack {
                if position.structuralStyle != 0, position.lastReadBook.isEmpty == false {
                    Text(position.lastReadBook)
                    if let percent = _positionViewModel?.percentFormatter.string(from: NSNumber(value: position.lastProgress / 100)) {
                        Text("(\(percent))")
                    }
                } else {
                    Text(position.lastReadChapter)
                    if let percent = _positionViewModel?.percentFormatter.string(from: NSNumber(value: position.lastChapterProgress / 100)) {
                        Text("(\(percent))")
                    }
                }
                Spacer()
                Text(position.epochByLocaleRelative).font(.caption)
            }
            if position.structuralStyle != 0, position.lastReadBook.isEmpty == false {
                HStack {
                    Spacer()
                    Text(position.lastReadChapter)
                    if let percent = _positionViewModel?.percentFormatter.string(from: NSNumber(value: position.lastChapterProgress / 100)) {
                        Text("(\(percent))")
                    }
                }.font(.caption)
            }
        }
    }
    
    @ViewBuilder
    private func row(obj: BookDeviceReadingPositionHistoryRealm) -> some View {
        VStack {
            HStack {
                Text("\(obj.endPosition?.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Chapter Unknown")")
                Spacer()
                Text("\(String(format: "%.2f%% Left", 100 - (obj.endPosition?.lastProgress ?? 0.0)))")
            }.font(.title3)
            HStack {
                Text(obj.endPosition?.epochByLocale ?? "End Unknown")
            }.font(.caption)
        }
    }
}

struct ReadingPositionHistoryView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    static var previews: some View {
        if let book = modelData.readingBook {
            NavigationView {
                ReadingPositionHistoryView(libraryId: book.library.id, bookId: book.id)
            }
            .navigationViewStyle(.stack)
            .environmentObject(modelData)
        }
    }
}
