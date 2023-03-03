//
//  LibraryInfoBatchDownloadSheet.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/6/15.
//

import SwiftUI

struct LibraryInfoBatchDownloadSheet: View {
    @EnvironmentObject var modelData: ModelData
    
    @Binding var presenting: Bool
    @Binding var downloadBookList: [CalibreBook]
    
    @State private var selected = Set<String>()
    @State private var formats = [String]()
    @State private var selectedFormats = [String: SelectedFormatInfo]()    //format to priority
    @State private var selectedFormatBooks = [CalibreBook]()
    
    @State private var editMode = EditMode.active
    
    var body: some View {
        NavigationView {
            List(selection: $selected) {
                ForEach(formats, id: \.self) { format in
                    if let selectFormatInfo = selectedFormats[format] {
                        HStack {
                            Text("\(format), \(selectFormatInfo.books.count) \(selectFormatInfo.books.count > 1 ? "books" : "book")")
                            
                            Spacer()
                            
                            Text(
                                ByteCountFormatter.string(fromByteCount: selectFormatInfo.totalSize, countStyle: .file)
                            )
                        }.tag(format)
                    }
                }
            }
            .navigationTitle(Text("Formats to Download"))
            .environment(\.editMode, $editMode)
            .onChange(of: selected, perform: { newValue in
                selectedFormatBooks = selectedFormats
                    .filter { newValue.contains($0.key) }
                    .reduce(into: Set<CalibreBook>(), { partialResult, entry in
                        partialResult.formUnion(entry.value.books)
                    }).map { $0 }
            })
            .onAppear() {
                selectedFormats = downloadBookList.reduce(into: [:]) { partialResult, book in
                    partialResult = book.formats.reduce(into: partialResult) { partialResult, formatEntry in
                        var selectFormatInfo = partialResult[formatEntry.key] ?? .init()
                        
                        selectFormatInfo.books.append(book)
                        selectFormatInfo.totalSize += Int64(formatEntry.value.serverSize)
                        
                        partialResult[formatEntry.key] = selectFormatInfo
                    }
                }
                
                formats = selectedFormats.keys.sorted()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presenting = false
                    }) {
                        Text("Cancel")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        presenting = false
                        
                        modelData.startBatchDownload(books: selectedFormatBooks, formats: Array(selectedFormats.keys))
                        
                        downloadBookList.removeAll()
                    }) {
                        Text("Download")
                    }
                }
            }
        }
        HStack {
            if selectedFormatBooks.count > 1 {
                Text("Will add \(selectedFormatBooks.count) books to shelf.")
            } else {
                Text("Will add \(selectedFormatBooks.count) book to shelf.")
            }
        }.padding()
    }
}

struct SelectedFormatInfo {
    var totalSize: Int64 = 0
    var books: [CalibreBook] = []
}

struct LibraryInfoBatchDownloadSheet_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)

    @State static private var presenting = true
    @State static private var downloadBookList = [CalibreBook]()
    
    static var previews: some View {
        LibraryInfoBatchDownloadSheet(presenting: $presenting, downloadBookList: $downloadBookList)
            .environmentObject(modelData)
    }
}
