//
//  MainView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI
import OSLog

@available(macCatalyst 14.0, *)
struct MainView: View {
    @EnvironmentObject var modelData: ModelData
    var defaultLog = Logger()
    var plainShelfUI = PlainShelfUI()
    
    @State private var calibreServer = "http://calibre-server.lan:8080/"
    @State private var result = "Waiting"
    @State private var activeTab = 0
    
    var body: some View {
        TabView(selection: $activeTab) {
            plainShelfUI
                .tabItem {
                    Image(systemName: "1.square.fill")
                    Text("Shelf")
                }
                .tag(1)
            
            VStack {
                HStack {
                    Text("Server:")
                    TextField("Server", text: $calibreServer)
                    Button("Connect") {
                        startLoad()
                    }
                }
                
                //LibraryInfoView(libraryInfo: $modelData.libraryInfo)
                LibraryInfoView()
            }
                .tabItem {
                    Image(systemName: "2.square.fill")
                    Text("Server")
                }
                .tag(2)
        }
        .font(.headline)
        .onChange(of: activeTab, perform: { index in
            if index == 1 {
                
            }
        })
        
    }
    
    func startLoad() {
        modelData.calibreServer = calibreServer
        let url = URL(string: calibreServer + "/ajax/library-info")!
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
            
            let libraryMap = libraryInfo["library_map"] as! [String: String]
            libraryMap.forEach { (key, value) in
                modelData.libraryInfo.addLibrary(name: key)
            }
        } catch {
        
        }
        
    }
    
}

@available(macCatalyst 14.0, *)
struct MainView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        MainView()
            .environmentObject(modelData)
        // ReaderView()
    }
}
