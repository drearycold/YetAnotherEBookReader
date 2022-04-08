//
//  ActivityList.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//

import SwiftUI

struct ActivityList: View {
    @EnvironmentObject var modelData: ModelData
    
    var libraryId: String? = nil
    var bookId: Int32? = nil
    
    var body: some View {
        NavigationView {
            List {
                ForEach(modelData.listCalibreActivities(libraryId: libraryId, bookId: bookId), id: \.self) { obj in
                    NavigationLink(destination: detail(obj: obj), label: {
                        row(obj: obj)
                    })
                }
            }
        }.frame(maxWidth: 500)
        .navigationViewStyle(StackNavigationViewStyle())
        .navigationTitle("Recent Activities")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func row(obj: CalibreActivityLogEntry) -> some View {
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
                Text(obj.type ?? "Unknown Type")
                Spacer()
                Text(obj.errMsg ?? "Unknown Error")
            }.font(.caption)
            HStack {
                Text(obj.startDateByLocale ?? "Start Unknown")
                Spacer()
                Text("->")
                Spacer()
                Text(obj.finishDateByLocale ?? "Finish Unknown")
            }.font(.caption)
        }
    }
    
    @ViewBuilder
    private func detail(obj: CalibreActivityLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let libraryId = obj.libraryId,
                   let library = modelData.calibreLibraries[libraryId] {
                    if let book = modelData.queryBookRealm(book: CalibreBook(id: obj.bookId, library: library), realm: modelData.realm) {
                        Text("Book Title:").frame(minWidth: 100, alignment: .leading)
                        Text(book.title)
                    } else {
                        Text("Library Name:").frame(minWidth: 100, alignment: .leading)
                        Text(library.name)
                    }
                } else {
                    Text("No Entity")
                }
                Spacer()
            }.font(.title2)
            HStack {
                Text("Task:").frame(minWidth: 100, alignment: .leading)
                Text(obj.type ?? "Unknown").navigationTitle(obj.type ?? "")
                Spacer()
            }.font(.title3)
            HStack {
                Text("Start time:").frame(minWidth: 100, alignment: .leading)
                Text(obj.startDateByLocaleLong ?? "Unknown")
            }
            
            HStack {
                Text("Finish time:").frame(minWidth: 100, alignment: .leading)
                Text(obj.finishDateByLocaleLong ?? "Unknown")
            }
            
            HStack {
                Text("Result:").frame(minWidth: 100, alignment: .leading)
                Text(obj.errMsg ?? "Unknown")
            }
            
            Divider().padding(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("More Infos")
                HStack {
                    Text("URL:").frame(minWidth: 64, alignment: .leading)
                    Text(obj.endpoingURL ?? "Unknown")
                }
                HStack {
                    Text("Method:").frame(minWidth: 64, alignment: .leading)
                    Text(obj.httpMethod ?? "GET")
                }
                HStack(alignment: .top) {
                    Text("Body:").frame(minWidth: 64, alignment: .leading)
                    if let httpBody = obj.httpBody, let httpBodyString = String(data: httpBody, encoding: .utf8) {
                        Text(httpBodyString)
                    } else {
                        Text("(Empty Body)")
                    }
                }
            }.font(.caption)
            
            Spacer()
        }
        .padding()
    }
}

struct ActivityList_Previews: PreviewProvider {
    static private var modelData = ModelData(mock: true)
    
    static var previews: some View {
        ActivityList()
            .environmentObject(modelData)
    }
}
