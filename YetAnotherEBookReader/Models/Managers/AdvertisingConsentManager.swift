import Foundation
import Combine
import UIKit
import AppTrackingTransparency
import OSLog
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform
#endif

/// Owns the single consent flow and gates every advertising entry point.
@MainActor
final class AdvertisingConsentManager: ObservableObject {
    static let shared = AdvertisingConsentManager()

    @Published private(set) var canRequestAds = false
    private var isGatheringConsent = false
    private let updateConsent: @MainActor () async throws -> Void
    private let presentConsent: @MainActor () async throws -> Void
    private let consentAllowsAds: @MainActor () -> Bool
    private let trackingAuthorizationRequired: @MainActor () -> Bool
    private let requestTracking: @MainActor () async throws -> Void
    private let startAds: @MainActor () async -> Void
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "AdvertisingConsent")

    init(
        updateConsent: @escaping @MainActor () async throws -> Void,
        presentConsent: @escaping @MainActor () async throws -> Void,
        consentAllowsAds: @escaping @MainActor () -> Bool,
        trackingAuthorizationRequired: @escaping @MainActor () -> Bool = { true },
        requestTracking: @escaping @MainActor () async throws -> Void,
        startAds: @escaping @MainActor () async -> Void
    ) {
        self.updateConsent = updateConsent
        self.presentConsent = presentConsent
        self.consentAllowsAds = consentAllowsAds
        self.trackingAuthorizationRequired = trackingAuthorizationRequired
        self.requestTracking = requestTracking
        self.startAds = startAds
    }

    func gatherConsent() async {
        guard !isGatheringConsent, !canRequestAds else { return }
        isGatheringConsent = true
        defer { isGatheringConsent = false }
        do {
            try await updateConsent()
            try await presentConsent()
            guard consentAllowsAds() else { return }
            if trackingAuthorizationRequired() {
                try await requestTracking()
            }
            await startAds()
            canRequestAds = true
        } catch {
            logger.error("Consent flow stopped; ads remain disabled: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum FlowError: Error { case inactive }

    func presentPrivacyOptions() async {
        #if canImport(GoogleMobileAds)
        guard canRequestAds, !isGatheringConsent else { return }
        isGatheringConsent = true
        canRequestAds = false
        defer { isGatheringConsent = false }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ConsentForm.presentPrivacyOptionsForm(from: nil) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            canRequestAds = ConsentInformation.shared.canRequestAds
        } catch {
            logger.error("Could not present privacy options: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private convenience init() {
        self.init(
            updateConsent: {
                #if canImport(GoogleMobileAds)
                let parameters = RequestParameters()
                parameters.isTaggedForUnderAgeOfConsent = false
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--consent-debug-reset") {
                    ConsentInformation.shared.reset()
                }
                if ProcessInfo.processInfo.arguments.contains("--consent-debug-eea") {
                    let settings = DebugSettings()
                    settings.geography = .EEA
                    parameters.debugSettings = settings
                }
                #endif
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                #endif
            },
            presentConsent: {
                #if canImport(GoogleMobileAds)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    ConsentForm.loadAndPresentIfRequired(from: nil) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
                #endif
            },
            consentAllowsAds: {
                #if canImport(GoogleMobileAds)
                return ConsentInformation.shared.canRequestAds
                #else
                return false
                #endif
            },
            trackingAuthorizationRequired: {
                ATTrackingManager.trackingAuthorizationStatus == .notDetermined
            },
            requestTracking: {
                guard UIApplication.shared.applicationState == .active else { throw FlowError.inactive }
                await withCheckedContinuation { continuation in
                    ATTrackingManager.requestTrackingAuthorization { _ in continuation.resume() }
                }
            },
            startAds: {
                #if canImport(GoogleMobileAds)
                await withCheckedContinuation { continuation in
                    MobileAds.shared.start { _ in continuation.resume() }
                }
                #endif
            }
        )
    }
}
