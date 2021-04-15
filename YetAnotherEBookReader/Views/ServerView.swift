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
    
    @State private var calibreServerUrl = ""
    @State private var calibreUsername = ""
    @State private var calibrePassword = ""
    //@State private var calibreServerEdit = CalibreServer(baseUrl: "", username: "", password: "")
    @State private var calibreServerLibrariesEdit = [CalibreLibrary]()
    
    @State private var enableStoreReadingPosition = false
    @State private var storeReadingPositionColumnName = ""
    @State private var enableCustomDictViewer = false
    @State private var customDictViewerURL = ""
    @State private var calibreServerEditing = false
    
    @State private var presentingAlert = false
    
    var defaultLog = Logger()

    struct AlertItem : Identifiable {
        var id: String
    }
    @State private var alertItem: AlertItem?
    @State private var alertContent: String = ""
    
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
                            TextField("Server", text: $calibreServerUrl)
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
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .border(Color(UIColor.separator))
                            
                        }
                        HStack {
                            Text("You entered: \(calibrePassword)")
                            Spacer()
                            Button(action:{ calibreServerEditing = false }) {
                                Image(systemName: "xmark")
                            }
                            Button(action:{ addServerConfirmButtonAction() }) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    HStack(alignment: .center, spacing: 8) {
                        Spacer()
                        
                        //Text(modelData.libraryInfo.description) //TODO
                        
                        Button(action: {
                            let ret = modelData.startLoad(
                                calibreServer: modelData.calibreServers[modelData.currentCalibreServerId]!,
                                success: modelData.handleLibraryInfo
                            )
                            if ret != 0 {
                                //TODO
                            }
                        }) {
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
        .alert(item: $alertItem) { item in
            if item.id == "AddServer" {
                return Alert(title: Text("Add Server"),
                             message: Text(alertContent),
                             primaryButton: .default(Text("Confirm")
                             ) {
                                 addServerConfirmed()
                             },
                             secondaryButton: .cancel())
            }
            if item.id == "AddServerExists" {
                return Alert(title: Text("Add Server"), message: Text("Duplicate"), dismissButton: .cancel())
            }
            return Alert(title: Text(item.id))
        }
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
                    let data = data {
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
    
    func handleLibraryInfo(jsonData: Data) {
        var calibreServer = CalibreServer(baseUrl: calibreServerUrl, username: calibreUsername, password: calibrePassword)
        
        if let libraryInfo = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? NSDictionary {
            defaultLog.info("libraryInfo: \(libraryInfo)")
            
            if let libraryMap = libraryInfo["library_map"] as? [String: String] {
                if let defaultLibrary = libraryInfo["default_library"] as? String {
                    calibreServer.defaultLibrary = defaultLibrary
                }
                var content = "Library List:"
                calibreServerLibrariesEdit.removeAll()
                libraryMap.forEach { (key, value) in
                    content += "\n\(value)"
                    calibreServerLibrariesEdit.append(CalibreLibrary(server: calibreServer, name: value))
                }
                
                alertContent = content
                alertItem = AlertItem(id: "AddServer")
            }
            
        } else {
            
        }
    }
    
    private func addServerConfirmButtonAction() {
        let calibreServer = CalibreServer(baseUrl: calibreServerUrl, username: calibreUsername, password: calibrePassword)
        if modelData.calibreServers[calibreServer.id] != nil {
            alertItem = AlertItem(id: "AddServerExists")
            return
        }
        print(calibreServer.password)
        let ret = modelData.startLoad(calibreServer: calibreServer, success: handleLibraryInfo)
        if ret != 0 {
            //TODO
        }
        
    }
    
    private func addServerConfirmed() {
        let calibreServer = CalibreServer(baseUrl: calibreServerUrl, username: calibreUsername, password: calibrePassword)
        
        modelData.addServer(server: calibreServer, libraries: calibreServerLibrariesEdit)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        ServerView()
            .environmentObject(modelData)
    }
}
