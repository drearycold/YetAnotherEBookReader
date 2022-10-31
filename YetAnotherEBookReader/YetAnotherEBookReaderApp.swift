//
//  YetAnotherEBookReaderApp.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI

@main
struct YetAnotherEBookReaderApp: App {
    @StateObject private var modelData = ModelData()
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var upgradingDatabase = false
    @State private var upgradingDatabaseStatus = ""
    
    var body: some Scene {
        WindowGroup {
//            ContentView()
//                .environment(\.managedObjectContext, persistenceController.container.viewContext)
            ZStack {
                MainView()
                    .environmentObject(modelData)
                
                if upgradingDatabase {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Upgrading Database Structure...")
                        Text(upgradingDatabaseStatus)
                    }
                    .padding()
                    .background(.gray.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .onChange(of: scenePhase) { newScenePhase in
            print("newScenePhase \(scenePhase) -> \(newScenePhase)")

            switch(newScenePhase) {
            case .active:
                modelData.registerGetBooksMetadataCancellable()
                if modelData.realm == nil {
                    upgradingDatabase = true
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try modelData.tryInitializeDatabase() { status in
                                upgradingDatabaseStatus = status
                            }
                            DispatchQueue.main.async {
                                modelData.initializeDatabase()
                                upgradingDatabase = false
                                
                                modelData.probeServersReachability(with: [], updateLibrary: true)
                                NotificationCenter.default.post(.init(name: .YABR_BookReaderEnterActive))
                            }
                        } catch {
                            upgradingDatabaseStatus = error.localizedDescription
                        }
                    }
                } else {
                    modelData.probeServersReachability(with: [], updateLibrary: true)
                    NotificationCenter.default.post(.init(name: .YABR_BookReaderEnterActive))
                }
                break
            case .inactive:
                break
            case .background:
                NotificationCenter.default.post(.init(name: .YABR_BookReaderEnterBackground))
                break
            @unknown default:
                break
            }
        }
    }
}
