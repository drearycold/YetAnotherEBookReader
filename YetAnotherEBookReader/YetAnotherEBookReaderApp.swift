//
//  YetAnotherEBookReaderApp.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI

@main
struct YetAnotherEBookReaderApp: App {
    enum LaunchState {
        case initializing(status: String)
        case ready
        case failed(message: String)
    }

    @StateObject private var container: AppContainer
    @StateObject private var mainViewModel: MainViewModel
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var launchState: LaunchState = .initializing(status: "Initializing...")
    @State private var bootstrapInFlight = false
    
    init() {
        let containerInstance = AppContainer()
        _container = StateObject(wrappedValue: containerInstance)
        _mainViewModel = StateObject(wrappedValue: MainViewModel(container: containerInstance, sessionManager: containerInstance.sessionManager))
        
        setupAppearance()
    }
    
    private func setupAppearance() {
        let woodColor = UIColor(ShelfLegacyMetrics.shelfBackgroundColor)
        
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = woodColor
        navBarAppearance.shadowColor = .clear
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = woodColor
        tabBarAppearance.shadowColor = .clear
        
        let normalTextAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.black.withAlphaComponent(0.6)]
        let selectedTextAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.systemBlue]
        let normalIconColor = UIColor.black.withAlphaComponent(0.5)
        let selectedIconColor = UIColor.systemBlue
        
        for layoutAppearance in [tabBarAppearance.stackedLayoutAppearance, tabBarAppearance.inlineLayoutAppearance, tabBarAppearance.compactInlineLayoutAppearance] {
            layoutAppearance.normal.iconColor = normalIconColor
            layoutAppearance.normal.titleTextAttributes = normalTextAttributes
            layoutAppearance.selected.iconColor = selectedIconColor
            layoutAppearance.selected.titleTextAttributes = selectedTextAttributes
        }
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                switch launchState {
                case .initializing(let status):
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Upgrading Database Structure...")
                        Text(status)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ShelfLegacyMetrics.shelfBackgroundColor)
                    
                case .failed(let message):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.largeTitle)
                        Text("Database Initialization Failed")
                            .font(.headline)
                        Text(message)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ShelfLegacyMetrics.shelfBackgroundColor)
                    
                case .ready:
                    MainView(container: container, viewModel: mainViewModel)
                        .environmentObject(container)
                }
            }
        }
        .onChange(of: scenePhase) { newScenePhase in
            switch(newScenePhase) {
            case .active:
                guard !bootstrapInFlight else { return }

                if case .ready = launchState, container.isDatabaseReady {
                    enableProbeTimer()
                    container.bookReaderActivitySubject.send(newScenePhase)
                } else {
                    bootstrapInFlight = true
                    launchState = .initializing(status: "Initializing...")
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try container.tryInitializeDatabase() { status in
                                DispatchQueue.main.async {
                                    launchState = .initializing(status: status)
                                }
                            }
                            DispatchQueue.main.async {
                                do {
                                    try container.initializeDatabase()
                                    launchState = .ready
                                    bootstrapInFlight = false
                                } catch {
                                    launchState = .failed(message: "Database failed to start: \(error.localizedDescription)")
                                    bootstrapInFlight = false
                                    return
                                }
                                enableProbeTimer()
                                container.bookReaderActivitySubject.send(newScenePhase)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                launchState = .failed(message: "Database initialization failed: \(error.localizedDescription)")
                                bootstrapInFlight = false
                            }
                        }
                    }
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
