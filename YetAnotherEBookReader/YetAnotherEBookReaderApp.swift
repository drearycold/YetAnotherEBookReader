//
//  YetAnotherEBookReaderApp.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI

@main
struct YetAnotherEBookReaderApp: App {
    private let container: AppContainer

    init() {
        let isUITestingMockLibrary = UITestingConfiguration.isEnabled()
        let containerInstance = isUITestingMockLibrary
            ? AppContainer(
                mock: true,
                testRealmEnvironment: TestRealmEnvironment.make(identifier: "UI-\(UUID().uuidString)")
            )
            : AppContainer()
        self.container = containerInstance
        if isUITestingMockLibrary {
            UserDefaults.standard.setValue(true, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
        }

        setupAppearance()
    }

    private func setupAppearance() {
        YabrAppChromeStyle.wood.applyAsDefaultAppearance()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(container: container)
        }
    }
}

@available(macCatalyst 14.0, *)
private struct AppRootView: View {
    enum LaunchState {
        case initializing(status: String)
        case ready
        case failed(message: String)
    }

    let container: AppContainer

    @StateObject private var mainViewModel: MainViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var sceneID = UUID()
    @State private var launchState: LaunchState
    @State private var bootstrapInFlight = false

    init(container: AppContainer) {
        self.container = container
        _mainViewModel = StateObject(wrappedValue: MainViewModel(container: container, sessionManager: container.sessionManager))
        _launchState = State(initialValue: container.isDatabaseReady ? .ready : .initializing(status: "Initializing..."))
    }

    var body: some View {
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
                    .environment(\.appContainer, container)
            }
        }
        .onContinueUserActivity(ReaderSceneActivity.activityType) { activity in
            mainViewModel.handleReaderSceneActivity(activity)
        }
        .onAppear {
            handleScenePhase(scenePhase)
        }
        .onDisappear {
            container.markAppSceneBackground(id: sceneID)
        }
        .onChange(of: scenePhase) { newScenePhase in
            handleScenePhase(newScenePhase)
        }
    }

    private func handleScenePhase(_ newScenePhase: ScenePhase) {
        mainViewModel.handleScenePhase(newScenePhase)

        switch(newScenePhase) {
        case .active:
            guard !bootstrapInFlight else { return }

            if case .ready = launchState, container.isDatabaseReady {
                handleDatabaseReady()
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
                            handleDatabaseReady()
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
            container.markAppSceneBackground(id: sceneID)
        @unknown default:
            break
        }
    }

    private func handleDatabaseReady() {
        mainViewModel.restorePersistedReadersIfNeeded()
        container.markAppSceneActive(id: sceneID)
    }
}
