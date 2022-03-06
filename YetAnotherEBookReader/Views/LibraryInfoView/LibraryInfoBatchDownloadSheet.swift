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
    @Binding var selectedBookIds: Set<String>
    
    @State private var formats = [String]()
    @State private var selectedFormat = [String: Int]()
    @State private var selectedFormatBookIds = [String]()
    
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text("Please Select Formats to Download")
            
            List {
                ForEach(formats, id: \.self) { format in
                    Button( action: {
                        if selectedFormat.keys.contains(format) {
                            selectedFormat.removeValue(forKey: format)
                        } else {
                            selectedFormat[format] = (selectedFormat.values.max() ?? 0) + 1
                        }
                        formats.sort {
                            let priorityLeft = selectedFormat[$0] ?? -1
                            let priorityRight = selectedFormat[$1] ?? -1
                            if priorityLeft > 0 && priorityRight > 0 {
                                return priorityLeft < priorityRight
                            } else if priorityLeft < 0 && priorityRight < 0 {
                                return $0 < $1
                            } else if priorityLeft < 0 {
                                return false
                            } else if priorityRight < 0 {
                                return true
                            } else {
                                return true
                            }
                        }
                        
                        selectedFormatBookIds = selectedBookIds.reduce(into: [String](), { result, bookId in
                            guard let book = modelData.getBookRealm(forPrimaryKey: bookId) else { return }
                            guard book.formats().keys.filter(selectedFormat.keys.contains).isEmpty == false else { return }
                            result.append(bookId)
                        })
                    }) {
                        HStack {
                            Text(format)
                            Spacer()
                            if selectedFormat.keys.contains(format) {
                                Image(systemName: "minus.circle")
                            } else {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
            }
            .onAppear() {
                formats = selectedBookIds.reduce(into: Set<String>()) { result, bookId in
                    guard let book = modelData.getBookRealm(forPrimaryKey: bookId) else { return }
                    result.formUnion(book.formats().keys)
                }.sorted()
                if formats.count == 1 {
                    selectedFormat[formats.first!] = 1
                }
            }
            .frame(height: CGFloat(200))
            
            if selectedBookIds.count > 1 {
                Text("Will add \(selectedFormatBookIds.count) books to shelf.")
            } else {
                Text("Will add \(selectedFormatBookIds.count) book to shelf.")
            }
            
            HStack(alignment: .center, spacing: 24) {
                Button(action: {
                    presenting = false
                    
                    modelData.startBatchDownload(bookIds: selectedFormatBookIds, formats: Array(selectedFormat.keys))
                }) {
                    Text("OK")
                }
                Button(action: {
                    presenting = false
                }) {
                    Text("Cancel")
                }
            }
        }.padding()
    }
    
    func test() {
//        selectedBookIds.forEach { bookId in
//            var downloaded = false
//            Format.allCases.forEach {
//                downloaded = downloaded || modelData.downloadFormat(book: modelData.calibreServerLibraryBooks[bookId]!, format: $0) { result in
//                    
//                }
//            }
//            if downloaded {
//                modelData.addToShelf(bookId, shelfName: "Untagged")
//            }
//        }
    }
}

//struct LibraryInfoBatchDownloadSheet_Previews: PreviewProvider {
//    static var previews: some View {
//        LibraryInfoBatchDownloadSheet()
//    }
//}
