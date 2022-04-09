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
        
    var libraryId: String?
    var bookId: Int32?
    
    @State private var readingStatistics = [Double]()
    @State private var maxMinutes = 0
    @State private var avgMinutes = 0
    var body: some View {
        VStack(spacing: 4) {
            
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    BarChartView(data: ChartData(points: readingStatistics), title: "Weekly Read Time", legend: "Minutes", form: ChartForm.large, valueSpecifier: "%.1f")
                    Spacer()
                }
                
                HStack {
                    Spacer()
                    Text("Of Last 7 Days: ")
                    Text("Max \(maxMinutes), Mean \(avgMinutes)")
                    Text("(Min./Day)")
                    Spacer()
                }
            }.padding([.top, .bottom], 8)
            
            Text("History").font(.title2)
            List {
                ForEach(modelData.listBookDeviceReadingPositionHistory(bookId: bookId, libraryId: libraryId), id: \.self) { obj in
                    NavigationLink(destination: detail(obj: obj), label: {
                        row(obj: obj)
                    })
                }
            }
        }.onAppear {
            readingStatistics = modelData.getReadingStatistics(bookId: bookId, libraryId: libraryId)
            maxMinutes = Int(readingStatistics.dropLast().max() ?? 0)
            avgMinutes = Int(readingStatistics.dropLast().reduce(0.0,+) / Double(readingStatistics.count - 1))
        }.frame(maxWidth: 500)
        .navigationTitle("Reading Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func row(obj: BookDeviceReadingPositionHistoryRealm) -> some View {
        VStack {
            HStack {
                if let libraryId = obj.libraryId,
                   let library = modelData.calibreLibraries[libraryId] {
                    if let book = modelData.queryBookRealm(book: CalibreBook(id: obj.bookId, library: library), realm: modelData.realm) {
                        Text(book.title)
                    } else {
                        Text(library.name)
                    }
                } else {
                    Text("No Entity")
                }
                Spacer()
                
            }
            HStack {
                Text("Chapter: \(obj.endPosition?.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Chapter Unknown")")
                Spacer()
                Text("\(String(format: "%.2f%% Left", 100 - (obj.endPosition?.lastProgress ?? 0.0)))")
            }.font(.caption)
            HStack {
                Text(obj.startDateByLocale ?? "Start Unknown")
                Spacer()
                Text("->")
                Spacer()
                Text(obj.endPosition?.epochByLocale ?? "End Unknown")
            }.font(.caption)
        }
    }
    
    @ViewBuilder
    private func detail(obj: BookDeviceReadingPositionHistoryRealm) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let libraryId = obj.libraryId,
                   let library = modelData.calibreLibraries[libraryId] {
                    if let bookId = bookId, let book = modelData.queryBookRealm(book: CalibreBook(id: bookId, library: library), realm: modelData.realm) {
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
            
            if let position = obj.endPosition {
                VStack(alignment: .leading) {
                    Text("Updated Position")
                        .font(.title3)
                    positionDetailView(position: position)
                        .navigationTitle("\(position.lastReadChapter), \(String(format: "%.0f%%", position.lastChapterProgress)) / \(String(format: "%.0f%%", position.lastProgress))")
                }
            }
            
            if let position = obj.startPosition {
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
                    Text("\(String(format: "%.2f%% Left", position.lastProgress))")
                }
                
                HStack {
                    Text("Datetime:")
                    Text(position.epochLocaleLong)
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

struct ReadingPositionHistoryView_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    static var previews: some View {
        ReadingPositionHistoryView(libraryId: "Default", bookId: 1)
            .environmentObject(modelData)
        
    }
}
