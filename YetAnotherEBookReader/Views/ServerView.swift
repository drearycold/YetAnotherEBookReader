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
    
    @State private var calibreServerId = ""
    @State private var calibreServerLibraryId = "Undetermined"
    
    @State private var calibreServer = ""
    @State private var calibreUsername = ""
    @State private var calibrePassword = ""
    
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
                    
                    Picker("Server: \(modelData.currentCalibreServerId)", selection: $calibreServerId) {
                        ForEach(modelData.calibreServers.values.sorted(by: { (lhs, rhs) -> Bool in
                            lhs.id < rhs.id
                        }), id: \.self) { server in
                            Text(server.id).tag(server.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: calibreServerId) { value in
                        modelData.currentCalibreServerId = calibreServerId
                    }
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
                        
                        //Text(modelData.libraryInfo.description) //TODO
                        
                        Button(action: { startLoad() }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Switch Library")
                    
                    Picker("Library: \(modelData.calibreServerLibraries[modelData.currentCalibreLibraryId]?.name ?? "")", selection: $calibreServerLibraryId) {
                        ForEach(modelData.calibreServerLibraries.values.sorted(by: { (lhs, rhs) -> Bool in
                            lhs.name < rhs.name
                        })) { library in
                            Text(library.name).tag(library.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .onChange(of: calibreServerLibraryId, perform: { value in
                        modelData.currentCalibreLibraryId = calibreServerLibraryId
                    })
                    
                        
                    HStack(alignment: .center, spacing: 8) {
                        Spacer()
                        
                        Text("\(modelData.calibreServerLibraryBooks.count) Book(s) in Library")
                        
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
            calibreServerId = modelData.currentCalibreServerId
            calibreServerLibraryId = modelData.currentCalibreLibraryId
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
        guard let url = URL(string: modelData.calibreServers[modelData.currentCalibreServerId]!.baseUrl + "/ajax/library-info") else {
            return
        }
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
                    modelData.handleLibraryInfo(jsonData: data)
                }
            }
        }
        task.resume()
    }
    
    
    private func syncLibrary() {
        print(modelData.calibreServerLibraries)
        print(modelData.currentCalibreLibraryId)
        guard let endpointUrl = URL(string: modelData.calibreServers[modelData.currentCalibreServerId]!.baseUrl + "/cdb/cmd/list/0?library_id=" + modelData.calibreServerLibraries[modelData.currentCalibreLibraryId]!.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else {
            return
        }
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
                            modelData.handleLibraryBooks(json: data)
                        }
                    }
                }

            task.resume()
                    
        }catch{
        }
    }
    
    private func updateLibrary() {
        
    }
    
    
}

struct SettingsView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        ServerView()
            .environmentObject(modelData)
    }
}
