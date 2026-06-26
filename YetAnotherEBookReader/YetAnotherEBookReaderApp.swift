//
//  YetAnotherEBookReaderApp.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI

@main
struct YetAnotherEBookReaderApp: App {
    @StateObject private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var upgradingDatabase = false
    @State private var upgradingDatabaseStatus = ""
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                MainView(viewModel: MainViewModel(container: container, sessionManager: container.sessionManager))
                    .environmentObject(container)
                    .environmentObject(container.downloadManager)
                    .environmentObject(container.sessionManager)
                    .environmentObject(container.fontsManager)
                
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
                if container.realm == nil {
                    upgradingDatabase = true
                    upgradingDatabaseStatus = "Initializing..."
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try container.tryInitializeDatabase() { status in
                                upgradingDatabaseStatus = status
                            }
                            DispatchQueue.main.async {
                                do {
                                    try container.initializeDatabase()
                                } catch {
                                    // Leave the upgrade overlay up; do not start
                                    // the probe timer or fire the activity subject
                                    // because the database is unusable.
                                    upgradingDatabaseStatus = "Database failed to start: \(error.localizedDescription)"
                                    return
                                }
                                upgradingDatabase = false

                                enableProbeTimer()
                                container.bookReaderActivitySubject.send(newScenePhase)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                upgradingDatabaseStatus = "Database initialization failed: \(error.localizedDescription)"
                            }
                        }
                    }
                } else {
                    enableProbeTimer()
                    container.bookReaderActivitySubject.send(newScenePhase)
                }
            case .inactive:
                break
            case .background:
                disableProbeTimer()
                container.bookReaderActivitySubject.send(newScenePhase)
                break
            @unknown default:
                break
            }
        }
    }
    
    func enableProbeTimer() {
        container.serverManager.probeServersReachability(with: [], updateLibrary: true)
        container.probeTimer = Timer.publish(every: 60, on: .main, in: .default)
            .autoconnect()
            .receive(on: DispatchQueue.main)
            .sink { timer in
//                container.probeServersReachability(with: [], updateLibrary: true)
            }
    }
    
    func disableProbeTimer() {
        container.probeTimer?.cancel()
    }
}
