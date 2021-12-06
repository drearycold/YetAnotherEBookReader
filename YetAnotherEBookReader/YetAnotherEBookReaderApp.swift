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
    
    var body: some Scene {
        WindowGroup {
//            ContentView()
//                .environment(\.managedObjectContext, persistenceController.container.viewContext)
            MainView()
                .environmentObject(modelData)
        }
        .onChange(of: scenePhase) { newScenePhase in
            print("newScenePhase \(scenePhase) -> \(newScenePhase)")

            switch(newScenePhase) {
            case .active:
                modelData.probeServersReachability(with: [])
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
