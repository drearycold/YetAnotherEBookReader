//
//  ReadingPositionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/2.
//

import SwiftUI
import RealmSwift

import SwiftUICharts

struct ReadingPositionHistoryView: View {
    @EnvironmentObject var modelData: ModelData
    
    @Binding var presenting: Bool
    
    @ObservedResults(BookDeviceReadingPositionRealm.self, where: { !$0.bookId.ends(with: " - History") }) var readingPositions

    let library: CalibreLibrary?
    let bookId: Int32?
    
    //model
    @State private var readingStatistics = [Double]()
    @State private var maxMinutes = 0
    @State private var avgMinutes = 0
    @State private var _positionViewModel: ReadingPositionListViewModel? = nil
    @State private var booksHistory = [String: Double]()   //InShelfId to minutes
    
    @State private var barChartData: BarChartData?
    
    let minutesFormatter = NumberFormatter()
    
    var body: some View {
        VStack {
            Group {
                if readingStatistics.isEmpty {
                    Text("New Book")
                } else {
                    #if DEBUG
                    List {
                        ForEach(readingStatistics, id: \.self) { minutes in
                            Text("\(minutes)")
                        }
                    }
                    #endif
                    if let data = barChartData {
                        BarChart(
                            chartData: data
                        )
                        .touchOverlay(chartData: data, specifier: "%.1f")
                        .averageLine(chartData: data,
                                     strokeStyle: StrokeStyle(lineWidth: 3,dash: [5,10]))
                        .yAxisPOI(chartData: data,
                                  markerName: "50",
                                  markerValue: 50,
                                  lineColour: Color.blue,
                                  strokeStyle: StrokeStyle(lineWidth: 3, dash: [5,10]))
                        .xAxisGrid(chartData: data)
                        .yAxisGrid(chartData: data)
                        .xAxisLabels(chartData: data)
                        .yAxisLabels(chartData: data)
                        .infoBox(chartData: data)
                        .floatingInfoBox(chartData: data)
                        .headerBox(chartData: data)
                        .legends(chartData: data)
                        .padding()
                    }
                }
            }
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
                
                #if DEBUG
                Text("BookId: \(bookId ?? -1)")
                Text("Library: \(library?.id ?? "NO LIB")")
                if let bookId = bookId,
                   let library = library {
                    ForEach(readingPositions.where({
                        $0.bookId.starts(
                            with: BookAnnotation.PrefId(library: library, id: bookId)
                        )
                    })) { readingPosition in
                        HStack {
                            Text(readingPosition.deviceId)
                            Text(readingPosition.lastReadChapter)
                            Text("\(readingPosition.lastProgress)")
                        }
                    }
                }
                #endif
                
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
                    #if debug
                    Text("Missing View Model")
                    #else
                    EmptyView()
                    #endif
                }
                
                Section(header: Text("Local Activities")) {
                    if let library = library, let bookId = bookId {
                        if let viewModel = _positionViewModel {
                            ForEach(modelData.listBookDeviceReadingPositionHistory(library: library, bookId: bookId).first?.value ?? [], id: \.self) { obj in
                                NavigationLink(
                                    destination: ReadingPositionDetailView(
                                        viewModel: ReadingPositionDetailViewModel(
                                            modelData: modelData,
                                            listModel: viewModel,
                                            position: obj.endPosition!)
                                    )
                                ) {
                                    row(position: obj.endPosition!)
                                }
                            }
                        }
                    } else {
                        ForEach(booksHistory.sorted(by: { $0.value > $1.value }), id: \.key) { inShelfId, minutes in
                            if let book = modelData.booksInShelf[inShelfId],
                               let minutesText = minutesFormatter.string(from: NSNumber(value: minutes)) {
                                NavigationLink(
                                    destination: ReadingPositionHistoryView(presenting: Binding<Bool>(get: { false }, set: { _ in }), library: book.library, bookId: book.id)
                                ) {
                                    HStack {
                                        Text(book.title)
                                        Spacer()
                                        Text(minutesText)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            let limitDays = 7
            let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(-86400 * (limitDays))))
            
            let readingHistoryList = modelData.listBookDeviceReadingPositionHistory(library: library, bookId: bookId, startDateAfter: startDate)
            
            readingStatistics = modelData.getReadingStatistics(list: readingHistoryList.flatMap({ $0.value }), limitDays: limitDays)
            maxMinutes = Int(readingStatistics.dropLast().max() ?? 0)
            avgMinutes = Int(readingStatistics.dropLast().reduce(0.0,+) / Double(readingStatistics.count - 1))
            
            barChartData = .init(
                dataSets: .init(
                    dataPoints: readingStatistics.map({
                        .init(value: $0)
                    }),
                    legendTitle: "Minutes"
                ),
                metadata: .init(
                    title: "Weekly Read Time",
                    subtitle: "Minutes"
                )
            )
            
            print("\(#function) readingStatistics=\(readingStatistics)")
            
            minutesFormatter.maximumFractionDigits = 1
            minutesFormatter.minimumFractionDigits = 1
            
            if let library = library, let bookId = bookId {
                if let bookRealm = modelData.queryBookRealm(book: CalibreBook(id: bookId, library: library), realm: modelData.realm),
                   let book = modelData.convert(bookRealm: bookRealm) {
                    _positionViewModel = ReadingPositionListViewModel(modelData: modelData, book: book, positions: book.readPos.getDevices())
                } else if let book = modelData.readingBook {
                    _positionViewModel = ReadingPositionListViewModel(modelData: modelData, book: book, positions: book.readPos.getDevices())
                }
            }
            else {
                self.booksHistory = readingHistoryList.reduce(into: [:], { partialResult, entry in
                    let inShelfId = entry.key
                    entry.value.forEach {
                        guard let endPosition = $0.endPosition else { return }
                        let duration = endPosition.epoch - $0.startDatetime.timeIntervalSince1970
                        if duration > 0 {
                            partialResult[inShelfId] = (partialResult[inShelfId] ?? 0.0) + (duration / 60.0)
                        }
                    }
                })
            }
        }
        .navigationTitle("Reading History")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func row(position: BookDeviceReadingPosition) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(position.readerName)
                Spacer()
            }.font(.caption)
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
            
            HStack {
                Spacer()
                if position.structuralStyle != 0, position.lastReadBook.isEmpty == false {
                    Text(position.lastReadChapter)
                    if let percent = _positionViewModel?.percentFormatter.string(from: NSNumber(value: position.lastChapterProgress / 100)) {
                        Text("(\(percent))")
                    }
                }
            }.font(.caption)
        }
    }

}

struct ReadingPositionHistoryView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var presenting = true
    
    static var previews: some View {
        if let book = modelData.readingBook {
            NavigationView {
                ReadingPositionHistoryView(presenting: $presenting, library: book.library, bookId: book.id)
            }
            .navigationViewStyle(.stack)
            .environmentObject(modelData)
        }
    }
}
