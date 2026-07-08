//
//  ReadingPositionHistoryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/2.
//

import SwiftUI

#if canImport(SwiftUICharts)
import SwiftUICharts
#endif

struct ReadingPositionHistoryView: View {
    @StateObject private var viewModel: ReadingPositionHistoryViewModel
    
    @Binding var presenting: Bool
    
    init(presenting: Binding<Bool>, library: CalibreLibrary?, bookId: Int32?) {
        self._presenting = presenting
        self._viewModel = StateObject(wrappedValue: ReadingPositionHistoryViewModel(library: library, bookId: bookId))
    }
    
    var body: some View {
        VStack {
            Group {
                if viewModel.readingStatistics.isEmpty {
                    Text("New Book")
                } else {
                    #if DEBUG
                    List {
                        ForEach(viewModel.readingStatistics, id: \.self) { minutes in
                            Text("\(minutes)")
                        }
                    }
                    #endif
                    #if canImport(SwiftUICharts)
                    if let data = viewModel.barChartData {
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
                    #endif
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
                Text("BookId: \(viewModel.bookId ?? -1)")
                Text("Library: \(viewModel.library?.id ?? "NO LIB")")
                ForEach(viewModel.debugReadingPositions, id: \.id) { readingPosition in
                    HStack {
                        Text(readingPosition.id)
                        Text(readingPosition.lastReadChapter)
                        Text("\(readingPosition.lastProgress)")
                    }
                }
                #endif
                
                if let listVM = viewModel.listViewModel {
                    if listVM.positions.isEmpty == false {
                        ForEach(listVM.positionsDeviceKeys(), id: \.self) { deviceId in
                            Section(
                                header: HStack {
                                    Text("On \(deviceId)")
                                    Spacer()
                                    if deviceId == viewModel.container.deviceName {
                                        Text("This Device").foregroundColor(.red)
                                    }
                                }
                            ) {
                                ForEach(listVM.positionsByLatestStyle(deviceId: deviceId), id: \.hashValue) { position in
                                    NavigationLink(
                                        destination: ReadingPositionDetailView(
                                            viewModel: ReadingPositionDetailViewModel(
                                                container: viewModel.container,
                                                listModel: listVM,
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
                        Text(getSavedUrl(book: listVM.book, format: Format.EPUB)?.absoluteString ?? "NO URL")
                        Text(getBookBaseUrl(id: listVM.book.id, library: listVM.book.library, localFilename: listVM.book.formats.first?.value.filename)?.absoluteString ?? "NIL")
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
                    if viewModel.library != nil, viewModel.bookId != nil {
                        if let listVM = viewModel.listViewModel {
                            ForEach(viewModel.localActivities, id: \.self) { obj in
                                if let endPos = obj.endPosition {
                                    NavigationLink(
                                        destination: ReadingPositionDetailView(
                                            viewModel: ReadingPositionDetailViewModel(
                                                container: viewModel.container,
                                                listModel: listVM,
                                                position: endPos)
                                        )
                                    ) {
                                        row(position: endPos)
                                    }
                                }
                            }
                        }
                    } else {
                        ForEach(viewModel.booksHistoryItems) { item in
                            NavigationLink(
                                destination: ReadingPositionHistoryView(presenting: Binding<Bool>(get: { false }, set: { _ in }), library: item.book.library, bookId: item.book.id)
                            ) {
                                HStack {
                                    Text(item.book.title)
                                    Spacer()
                                    Text(item.minutesText)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadData()
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
                    if let percent = viewModel.listViewModel?.percentFormatter.string(from: NSNumber(value: position.lastProgress / 100)) {
                        Text("(\(percent))")
                    }
                } else {
                    Text(position.lastReadChapter)
                    if let percent = viewModel.listViewModel?.percentFormatter.string(from: NSNumber(value: position.lastChapterProgress / 100)) {
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
                    if let percent = viewModel.listViewModel?.percentFormatter.string(from: NSNumber(value: position.lastChapterProgress / 100)) {
                        Text("(\(percent))")
                    }
                }
            }.font(.caption)
        }
    }

}

struct ReadingPositionHistoryView_Previews: PreviewProvider {
    static private var container = AppContainer(mock: true)

    @State static private var presenting = true
    
    static var previews: some View {
        if let book = container.bookManager.booksInShelf.values.first {
            NavigationView {
                ReadingPositionHistoryView(presenting: $presenting, library: book.library, bookId: book.id)
            }
            .navigationViewStyle(.stack)
            .environment(\.appContainer, container)
        }
    }
}
