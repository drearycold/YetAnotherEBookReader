//
//  SettingsView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/3/31.
//

import SwiftUI
import OSLog

struct ServerView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var calibreServer = "http://calibre-server.lan:8080/"
    @State private var calibreUsername = ""
    @State private var calibrePassword = ""
    @State private var calibreLibrary = "Undetermined"
    @State private var enableStoreReadingPosition = false
    @State private var storeReadingPositionColumnName = ""
    @State private var enableCustomDictViewer = false
    @State private var customDictViewerURL = ""
    @State private var calibreServerEditing = false
    
    @State private var result = "Waiting"
    
    var defaultLog = Logger()

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {} ) {
                    Image(systemName: "ellipsis.circle")
                }
            }.padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8))
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Switch Server")
                        Spacer()
                        Button(action:{ calibreServerEditing = true }) {
                            Image(systemName: "plus")
                        }
                        Button(action:{}) {
                            Image(systemName: "minus")
                        }
                        Button(action:{}) {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                    
                    Picker("Server: \(modelData.calibreServerDescription)", selection: $calibreServer) {
                        ForEach(modelData.libraryInfo.libraries) { library in
                            Text(library.id).tag(library.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: calibreLibrary, perform: { value in
                        modelData.calibreLibrary = calibreLibrary
                    })
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    if calibreServerEditing {
                        HStack {
                            Text("Server:")
                            TextField("Server", text: $calibreServer)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))

                        }
                        HStack {
                            Text("Username:")
                            TextField("Username", text: $calibreUsername)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))
                        }
                        HStack {
                            Text("Password:")
                            SecureField("Password", text: $calibrePassword)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))
                            
                        }
                        HStack {
                            Spacer()
                            Button(action:{ calibreServerEditing = false }) {
                                Image(systemName: "xmark")
                            }
                            Button(action:{ }) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    HStack(alignment: .center, spacing: 8) {
                        Spacer()
                        
                        Text(modelData.libraryInfo.description)
                        
                        Button(action: { startLoad() }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Switch Library")
                    
                    Picker("Library: \(calibreLibrary)", selection: $calibreLibrary) {
                        ForEach(modelData.libraryInfo.libraries) { library in
                            Text(library.id).tag(library.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: calibreLibrary, perform: { value in
                        modelData.calibreLibrary = calibreLibrary
                    })
                    
                        
                    HStack(alignment: .center, spacing: 8) {
                        Spacer()
                        
                        Text("\(modelData.getLibrary()?.books.count ?? 0) Book(s) in Library")
                        
                        Button(action: { syncLibrary() }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                       
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("More Settings")
                    
                    Toggle("Store Reading Position in Custom Column", isOn: $enableStoreReadingPosition)
                    if enableStoreReadingPosition {
                        HStack {
                            Text("Column Name:")
                            TextField("#column", text: $storeReadingPositionColumnName, onCommit: {
                                modelData.updateStoreReadingPosition(enabled: enableStoreReadingPosition, value: storeReadingPositionColumnName)
                            })
                                .keyboardType(.alphabet)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))
                        }
                    }
                    
                    Toggle("Enable Custom Dictionary Viewer", isOn: $enableCustomDictViewer)
                    if enableCustomDictViewer {
                        HStack {
                            Text("URL:")
                            TextField("", text: $customDictViewerURL, onCommit: {
                                modelData.updateCustomDictViewer(enabled: enableCustomDictViewer, value: customDictViewerURL)
                            })
                                .keyboardType(.alphabet)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))
                        }
                    }
                }.onChange(of: enableStoreReadingPosition) { value in
                    modelData.updateStoreReadingPosition(enabled: enableStoreReadingPosition, value: storeReadingPositionColumnName)
                }.onChange(of: enableCustomDictViewer) { value in
                    modelData.updateCustomDictViewer(enabled: enableCustomDictViewer, value: customDictViewerURL)
                }
                
                Spacer()
            }.padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
        }
        
        .onAppear() {
            calibreServer = modelData.calibreServer
            calibreUsername = modelData.calibreUsername
            calibrePassword = modelData.calibrePassword
            calibreLibrary = modelData.calibreLibrary
        }
        .navigationBarHidden(false)
        .statusBar(hidden: false)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action:{
                    
                }) {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    func startLoad() {
        modelData.calibreServer = calibreServer
        modelData.calibreUsername = calibreUsername
        modelData.calibrePassword = calibrePassword
        let url = URL(string: calibreServer + "/ajax/library-info")!
        if calibreUsername.count > 0 && calibrePassword.count > 0 {
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port!,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            let userCredential = URLCredential(user: calibreUsername,
                                               password: calibrePassword,
                                               persistence: .permanent)
            URLCredentialStorage.shared.setDefaultCredential(userCredential, for: protectionSpace)
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                // self.handleClientError(error)
                result = error.localizedDescription
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode) else {
                // self.handleServerError(response)
                result = "not httpResponse"
                return
            }
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                let data = data,
                let string = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    //self.webView.loadHTMLString(string, baseURL: url)
                    result = string
                    handleLibraryInfo(jsonData: data)
                }
            }
        }
        task.resume()
    }
    
    func handleLibraryInfo(jsonData: Data) {
        do {
            let libraryInfo = try JSONSerialization.jsonObject(with: jsonData, options: []) as! NSDictionary
            defaultLog.info("libraryInfo: \(libraryInfo)")
            
            // modelData.libraryInfo.reset()
            let libraryMap = libraryInfo["library_map"] as! [String: String]
            libraryMap.forEach { (key, value) in
                modelData.libraryInfo.getLibrary(name: key)
            }
            if libraryMap[calibreLibrary] == nil {
                calibreLibrary = libraryInfo["default_library"] as? String ?? "Calibre Library"
            }
        } catch {
        
        }
        
    }
    
    private func syncLibrary() {
        let endpointUrl = URL(string: modelData.calibreServer + "/cdb/cmd/list/0?library_id=" + calibreLibrary.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        let json:[Any] = [["title", "authors", "formats", "rating"], "", "", "", -1]
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
        guard let library = modelData.getLibrary() else {
            return
        }
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
                    book.libraryName = calibreLibrary
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
            
            let ratings = dataElement["rating"] as! NSDictionary
            ratings.forEach { (key, value) in
                let id = (key as! NSString).intValue
                if let rating = value as? NSNumber {
                    booksMap[id]!.rating = rating.intValue
                }
            }
            
        } catch {
        
        }
        
        modelData.libraryInfo.libraryMap[calibreLibrary]!.updateBooks(booksMap)
        
    }
}

struct SettingsView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        ServerView()
            .environmentObject(modelData)
    }
}
