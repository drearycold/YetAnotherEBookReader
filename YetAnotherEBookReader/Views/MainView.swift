//
//  MainView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI

@available(macCatalyst 14.0, *)
struct MainView: View {
    @EnvironmentObject var modelData: ModelData
    
    @State private var activeTab = 0
    
    var body: some View {
        TabView(selection: $activeTab) {
            SectionShelfUI()
                .tabItem {
                    Image(systemName: "0.square.fill")
                    Text("Shelf")
                }
                .tag(0)
                
            PlainShelfUI()
                .tabItem {
                    Image(systemName: "1.square.fill")
                    Text("Shelf")
                }
                .tag(1)
            
            
            LibraryInfoView()
                .tabItem {
                    Image(systemName: "2.square.fill")
                    Text("Library")
                }
                .tag(2)
            
            ServerView()
                .tabItem {
                    Image(systemName: "3.square.fill")
                    Text("Server")
                }
                .tag(3)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .font(.headline)
        .onChange(of: activeTab, perform: { index in
            if index == 1 {
                
            }
            
            if index == 3 {
                // startLoad()
            }
        })
        
        
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
