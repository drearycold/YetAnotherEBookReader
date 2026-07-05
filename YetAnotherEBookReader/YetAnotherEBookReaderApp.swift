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

    private let container: AppContainer
    @StateObject private var mainViewModel: MainViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var launchState: LaunchState = .initializing(status: "Initializing...")
    @State private var bootstrapInFlight = false
    @State private var probeTimerTask: Task<Void, Never>?

    private static let probeIntervalNanoseconds: UInt64 = 60 * 1_000_000_000
    private static let uiTestingMockLibraryArgument = "--ui-testing-mock-library"

    init() {
        let isUITestingMockLibrary = ProcessInfo.processInfo.arguments.contains(Self.uiTestingMockLibraryArgument)
        let containerInstance = isUITestingMockLibrary
            ? AppContainer(
                mock: true,
                testRealmEnvironment: TestRealmEnvironment.make(identifier: "UI-\(UUID().uuidString)")
            )
            : AppContainer()
        self.container = containerInstance
        _mainViewModel = StateObject(wrappedValue: MainViewModel(container: containerInstance, sessionManager: containerInstance.sessionManager))
        if isUITestingMockLibrary {
            _launchState = State(initialValue: .ready)
            UserDefaults.standard.setValue(true, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
        }

        setupAppearance()
    }

    private func setupAppearance() {
        YabrAppChromeStyle.wood.applyAsDefaultAppearance()
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
                        .environment(\.appContainer, container)
                }
            }
        }
        .onChange(of: scenePhase) { newScenePhase in
            switch(newScenePhase) {
            case .active:
                guard !bootstrapInFlight else { return }

                if case .ready = launchState, container.isDatabaseReady {
                    enableProbeTimer()
                    container.publishBookReaderActivity(newScenePhase)
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
                                container.publishBookReaderActivity(newScenePhase)
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
                container.publishBookReaderActivity(newScenePhase)
                break
            @unknown default:
                break
            }
        }
    }

    @MainActor
    func enableProbeTimer() {
        probeTimerTask?.cancel()
        container.serverManager.probeServersReachability(with: [], updateLibrary: true)
        probeTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.probeIntervalNanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                container.serverManager.probeServersReachability(with: [], updateLibrary: true)
            }
        }
    }

    @MainActor
    func disableProbeTimer() {
        probeTimerTask?.cancel()
        probeTimerTask = nil
    }
}
