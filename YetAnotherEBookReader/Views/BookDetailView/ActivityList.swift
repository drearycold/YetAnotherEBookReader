//
//  ActivityList.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/11/1.
//
import SwiftUI
import RealmSwift

struct ActivityList: View {
    @EnvironmentObject var modelData: ModelData

    @Binding var presenting: Bool

    var libraryId: String? = nil
    var bookId: Int32? = nil

    @ObservedResults(
        CalibreActivityLogEntry.self,
        configuration: ModelData.shared?.realmConf,
        sortDescriptor: SortDescriptor(keyPath: "startDatetime", ascending: false)
    ) var activities

    init(presenting: Bool? = nil, libraryId: String? = nil, bookId: Int32? = nil) {
        self._presenting = Binding<Bool>(get: { presenting ?? false }, set: { _ in })
        self.libraryId = libraryId
        self.bookId = bookId
        
        let cutoff = Date(timeIntervalSinceNow: -86400 * 7)  // Show last 7 days
        var predicate = NSPredicate(format: "startDatetime >= %@", cutoff as NSDate)
        
        if let libraryId = libraryId {
            if let bookId = bookId {
                predicate = NSPredicate(format: "startDatetime >= %@ AND libraryId == %@ AND bookId == %d", cutoff as NSDate, libraryId, bookId)
            } else {
                predicate = NSPredicate(format: "startDatetime >= %@ AND libraryId == %@", cutoff as NSDate, libraryId)
            }
        }
        
        _activities = ObservedResults(
            CalibreActivityLogEntry.self,
            configuration: ModelData.shared?.realmConf,
            filter: predicate,
            sortDescriptor: SortDescriptor(keyPath: "startDatetime", ascending: false)
        )
        print("ActivityList initialized with Realm URL: \(activities.realm?.configuration.fileURL?.absoluteString ?? "Unknown")")
    }
    
    init(presenting: Binding<Bool>, libraryId: String? = nil, bookId: Int32? = nil) {
        self._presenting = presenting
        self.libraryId = libraryId
        self.bookId = bookId
        
        let cutoff = Date(timeIntervalSinceNow: -86400 * 7)  // Show last 7 days
        var predicate = NSPredicate(format: "startDatetime >= %@", cutoff as NSDate)
        
        if let libraryId = libraryId {
            if let bookId = bookId {
                predicate = NSPredicate(format: "startDatetime >= %@ AND libraryId == %@ AND bookId == %d", cutoff as NSDate, libraryId, bookId)
            } else {
                predicate = NSPredicate(format: "startDatetime >= %@ AND libraryId == %@", cutoff as NSDate, libraryId)
            }
        }
        
        _activities = ObservedResults(
            CalibreActivityLogEntry.self,
            configuration: ModelData.shared?.realmConf,
            filter: predicate,
            sortDescriptor: SortDescriptor(keyPath: "startDatetime", ascending: false)
        )
        print("ActivityList initialized with Realm URL: \(activities.realm?.configuration.fileURL?.absoluteString ?? "Unknown")")
    }

    var body: some View {
        List {
            ForEach(activities, id: \.self) { obj in
                NavigationLink(destination: ActivityDetailView(obj: obj), label: {
                    row(obj: obj)
                })
            }
        }
        .navigationTitle("Recent Activities")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction, content: {
                if presenting {
                    Button(action: {
                        presenting = false
                    }) {
                        Image(systemName: "xmark")
                    }
                } else {
                    EmptyView()
                }
            })
        }
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
}

struct ActivityDetailView: View {
    @EnvironmentObject var modelData: ModelData
    var obj: CalibreActivityLogEntry
    
    var body: some View {
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
    
    @State static private var presenting = false
    static var previews: some View {
        NavigationView {
            ActivityList(presenting: $presenting)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environmentObject(modelData)
    }
}
