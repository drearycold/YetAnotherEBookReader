//
//  LibraryView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import SwiftUI
import OSLog


@available(macCatalyst 14.0, *)
struct LibraryView: View {
    @EnvironmentObject var modelData: ModelData
    var defaultLog = Logger()
    
    @Binding var library: Library
    @State var searchString = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Library: " + library.name)
                Spacer()
                Button(action: { syncLibrary() }) {
                    Text("Sync")
                }
            }
            TextField("Search", text: $searchString, onCommit: {
                library.filterBooks(searchString)
            })
            
            NavigationView {
                List {
                    ForEach(library.books.indices, id: \.self) { index in
                        NavigationLink(destination: BookDetailView(book: Binding<Book>(
                            get: {
//                                var book = library.books[index]
//                                if( !book.inShelf ) {
//                                    print("INSHELF \(library) \(library.books) \(index) \(book.title) \(book.inShelf)")
//                                }
                                return modelData.libraryInfo.libraryMap[library.name]!.books[index]
                            },
                            set: { newBook in
                                library.books[index] = newBook
                                library.booksMap[newBook.id] = newBook
                            }
                        ))) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(library.books[index].title)").font(.headline)
                                Text("\(library.books[index].authors)").font(.subheadline)
                            }
                        }
                    }
                }
                .navigationBarTitle("Pick a Book")
            }
            .navigationViewStyle(DoubleColumnNavigationViewStyle())
        }
    }
    
    private func syncLibrary() {
        let endpointUrl = URL(string: modelData.calibreServer + "/cdb/cmd/list/0?library_id=" + library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        let json:[Any] = [["title", "authors", "formats"], "", "", "", -1]
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            
            var request = URLRequest(url: endpointUrl)
            request.httpMethod = "POST"
            request.httpBody = data
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    // self.handleClientError(error)
                    defaultLog.warning("error: \(error.localizedDescription)")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                    (200...299).contains(httpResponse.statusCode) else {
                    // self.handleServerError(response)
                    defaultLog.warning("not httpResponse: \(response.debugDescription)")
                    return
                }
                
                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                    let data = data,
                    let string = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            //self.webView.loadHTMLString(string, baseURL: url)
                            //result = string
                            handleLibraryBooks(json: data)
                        }
                    }
                }

            task.resume()
                    
        }catch{
        }
    }
    
    private func updateLibrary() {
        
    }
    
    func handleLibraryBooks(json: Data) {
        var booksMap = library.booksMap
        
        do {
            let root = try JSONSerialization.jsonObject(with: json, options: []) as! NSDictionary
            let resultElement = root["result"] as! NSDictionary
            let bookIds = resultElement["book_ids"] as! NSArray
            
            bookIds.forEach { idNum in
                let id = (idNum as! NSNumber).int32Value
                if booksMap[id] == nil {
                    var book = Book(serverInfo: ServerInfo(calibreServer: modelData.calibreServer))
                    book.id = id
                    book.libraryName = library.name
                    booksMap[book.id] = book
                }
            }
            
            let dataElement = resultElement["data"] as! NSDictionary
            
            let titles = dataElement["title"] as! NSDictionary
            titles.forEach { (key, value) in
                let id = (key as! NSString).intValue
                let title = value as! String
                booksMap[id]!.title = title
            }
            
            let authors = dataElement["authors"] as! NSDictionary
            authors.forEach { (key, value) in
                let id = (key as! NSString).intValue
                let authors = value as! NSArray
                booksMap[id]!.authors = authors[0] as? String ?? "Unknown"
            }
            
            let formats = dataElement["formats"] as! NSDictionary
            formats.forEach { (key, value) in
                let id = (key as! NSString).intValue
                let formats = value as! NSArray
                formats.forEach { format in
                    booksMap[id]!.formats[(format as! String)] = ""
                }
            }
            
        } catch {
        
        }
        
        library.booksMap = booksMap
        library.filterBooks(searchString)
    }
}

@available(macCatalyst 14.0, *)
struct LibraryView_Previews: PreviewProvider {
    @State static private var library = Library(name: "Calibre-Default")
    static var previews: some View {
        LibraryView(library: $library)
            .environmentObject(ModelData())
    }
}
