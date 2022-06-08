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
        List {
            Section(
                header: Text("Stats"),
                footer: HStack {
                    Spacer()
                    Text("Of Last 7 Days: Max \(maxMinutes), Mean \(avgMinutes) (Min./Day)")
                }
            ) {
                BarChartView(data: ChartData(points: readingStatistics), title: "Weekly Read Time", legend: "Minutes", form: ChartForm.large, valueSpecifier: "%.1f")
            }
            Section(header: Text("History")) {
                ForEach(modelData.listBookDeviceReadingPositionHistory(bookId: bookId, libraryId: libraryId), id: \.self) { obj in
                    NavigationLink(destination: ReadingPositionHistoryDetailView(positionHistory: obj), label: {
                        row(obj: obj)
                    })
                }
            }
        }
        .onAppear {
            readingStatistics = modelData.getReadingStatistics(bookId: bookId, libraryId: libraryId)
            maxMinutes = Int(readingStatistics.dropLast().max() ?? 0)
            avgMinutes = Int(readingStatistics.dropLast().reduce(0.0,+) / Double(readingStatistics.count - 1))
        }
        .navigationTitle("Reading History")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func row(obj: BookDeviceReadingPositionHistoryRealm) -> some View {
        VStack {
//            HStack {
//                if let libraryId = obj.libraryId,
//                   let library = modelData.calibreLibraries[libraryId] {
//                    if let book = modelData.queryBookRealm(book: CalibreBook(id: obj.bookId, library: library), realm: modelData.realm) {
//                        Text(book.title)
//                    } else {
//                        Text(library.name)
//                    }
//                } else {
//                    Text("No Entity")
//                }
//                Spacer()
//
//            }
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
        ReadingPositionHistoryView(libraryId: "Default", bookId: 1)
            .environmentObject(modelData)
        
    }
}
