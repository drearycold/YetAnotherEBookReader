//
//  SwiftUI_Ad_Banner.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/2.
//

import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(GoogleMobileAds)
private struct BannerVC: UIViewControllerRepresentable {
    let adUnitID: String
    let adSize: AdSize
    
    init(adUnitID: String, adSize: AdSize) {
        self.adUnitID = adUnitID
        self.adSize = adSize
    }
    
    func makeUIViewController(context: Context) -> BannerHostingViewController {
        let viewController = BannerHostingViewController()
        viewController.configure(adUnitID: adUnitID, adSize: adSize)
        return viewController
    }

    func updateUIViewController(_ uiViewController: BannerHostingViewController, context: Context) {
        uiViewController.configure(adUnitID: adUnitID, adSize: adSize)
    }
}

private final class BannerHostingViewController: UIViewController {
    private let bannerView = BannerView(adSize: AdSizeBanner)
    private var loadedAdUnitID: String?
    private var loadedAdSize: CGSize?

    override func viewDidLoad() {
        super.viewDidLoad()

        bannerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bannerView)

        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func configure(adUnitID: String, adSize: AdSize) {
        let size = adSize.size
        view.frame = CGRect(origin: .zero, size: size)
        view.bounds = CGRect(origin: .zero, size: size)

        let shouldReload = loadedAdUnitID != adUnitID || loadedAdSize != size
        bannerView.adUnitID = adUnitID
        bannerView.adSize = adSize
        bannerView.rootViewController = self

        guard shouldReload else { return }

        loadedAdUnitID = adUnitID
        loadedAdSize = size
        bannerView.load(Request())
    }
}
#endif

struct Banner: View {
    @Environment(\.appContainer) var container
    
    var body: some View {
        HStack {
            if let adUnitID = YabrAppInfo.shared.gadBannerShelfUnitID {
                Spacer()
                #if canImport(GoogleMobileAds)
                BannerVC(adUnitID: adUnitID, adSize: AdSizeBanner)
                    .frame(width: AdSizeBanner.size.width, height: AdSizeBanner.size.height, alignment: .center)
                #endif
                Spacer()
            }
        }
    }
}

struct AdaptiveBanner: View {
    let width: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        #if canImport(GoogleMobileAds)
        if let adUnitID = YabrAppInfo.shared.gadBannerShelfUnitID {
            let resolvedWidth = max(1, floor(width))
            let resolvedHeight = max(50, maxHeight)
            let adSize = inlineAdaptiveBanner(width: resolvedWidth, maxHeight: resolvedHeight)

            BannerVC(adUnitID: adUnitID, adSize: adSize)
                .frame(width: resolvedWidth, height: resolvedHeight, alignment: .center)
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}

struct MediumRectangleBanner: View {
    var body: some View {
        #if canImport(GoogleMobileAds)
        if let adUnitID = YabrAppInfo.shared.gadBannerShelfUnitID {
            BannerVC(adUnitID: adUnitID, adSize: AdSizeMediumRectangle)
                .frame(
                    width: AdSizeMediumRectangle.size.width,
                    height: AdSizeMediumRectangle.size.height,
                    alignment: .center
                )
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}

enum ShelfNativeAdCacheStatus: Equatable {
    case missing
    case loaded
    case failed
}

final class ShelfNativeAdStore: ObservableObject {
    static let maximumEntryCount = 8
    static let loadedAdLifetime: TimeInterval = 55 * 60
    static let failedAdCooldown: TimeInterval = 60

    @Published private(set) var revision = 0

    private struct Entry {
        let status: ShelfNativeAdCacheStatus
        let expiresAt: Date
        var lastAccess: UInt64
    }

    private let now: () -> Date
    private var entries: [String: Entry] = [:]
    private var accessCounter: UInt64 = 0

    #if canImport(GoogleMobileAds)
    private var nativeAds: [String: NativeAd] = [:]
    #endif

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func status(for slotID: String) -> ShelfNativeAdCacheStatus {
        pruneExpiredEntries()

        guard var entry = entries[slotID] else { return .missing }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        entries[slotID] = entry
        return entry.status
    }

    #if canImport(GoogleMobileAds)
    func nativeAd(for slotID: String) -> NativeAd? {
        guard status(for: slotID) == .loaded else { return nil }
        return nativeAds[slotID]
    }

    func recordLoaded(_ nativeAd: NativeAd, for slotID: String) {
        nativeAds[slotID] = nativeAd
        record(status: .loaded, lifetime: Self.loadedAdLifetime, for: slotID)
    }
    #endif

    func recordLoadedForTesting(for slotID: String) {
        record(status: .loaded, lifetime: Self.loadedAdLifetime, for: slotID)
    }

    func recordFailure(for slotID: String) {
        #if canImport(GoogleMobileAds)
        nativeAds.removeValue(forKey: slotID)
        #endif
        record(status: .failed, lifetime: Self.failedAdCooldown, for: slotID)
    }

    func clear() {
        entries.removeAll(keepingCapacity: false)
        #if canImport(GoogleMobileAds)
        nativeAds.removeAll(keepingCapacity: false)
        #endif
        revision &+= 1
    }

    private func record(status: ShelfNativeAdCacheStatus, lifetime: TimeInterval, for slotID: String) {
        pruneExpiredEntries()
        accessCounter &+= 1
        entries[slotID] = Entry(
            status: status,
            expiresAt: now().addingTimeInterval(lifetime),
            lastAccess: accessCounter
        )
        trimToLimit()
        revision &+= 1
    }

    private func pruneExpiredEntries() {
        let currentDate = now()
        let expiredSlotIDs = entries.compactMap { slotID, entry in
            entry.expiresAt <= currentDate ? slotID : nil
        }

        expiredSlotIDs.forEach(removeEntry)
    }

    private func trimToLimit() {
        while entries.count > Self.maximumEntryCount,
              let leastRecentlyUsed = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            removeEntry(for: leastRecentlyUsed)
        }
    }

    private func removeEntry(for slotID: String) {
        entries.removeValue(forKey: slotID)
        #if canImport(GoogleMobileAds)
        nativeAds.removeValue(forKey: slotID)
        #endif
    }
}

fileprivate enum ShelfNativeAdLayout: Equatable {
    case endcap(width: CGFloat)
    case strip(width: CGFloat)

    var contentWidth: CGFloat {
        switch self {
        case .endcap(let width), .strip(let width):
            return width
        }
    }
}

#if canImport(GoogleMobileAds)
private enum ShelfNativeAdLoadState {
    case loaded(NativeAd)
    case failed
}

private struct ShelfNativeAdVC: UIViewControllerRepresentable {
    let slotID: String
    let layout: ShelfNativeAdLayout
    let nativeAdUnitID: String
    let bannerAdUnitID: String?
    let store: ShelfNativeAdStore

    func makeUIViewController(context: Context) -> ShelfNativeAdViewController {
        let viewController = ShelfNativeAdViewController()
        viewController.configure(
            slotID: slotID,
            layout: layout,
            nativeAdUnitID: nativeAdUnitID,
            bannerAdUnitID: bannerAdUnitID,
            store: store
        )
        return viewController
    }

    func updateUIViewController(_ uiViewController: ShelfNativeAdViewController, context: Context) {
        uiViewController.configure(
            slotID: slotID,
            layout: layout,
            nativeAdUnitID: nativeAdUnitID,
            bannerAdUnitID: bannerAdUnitID,
            store: store
        )
    }
}

private final class ShelfNativeAdViewController: UIViewController {
    private var adLoader: AdLoader?
    private var configuredSlotID: String?
    private var configuredLayout: ShelfNativeAdLayout?
    private var configuredNativeAdUnitID: String?
    private var configuredBannerAdUnitID: String?
    private var store: ShelfNativeAdStore?
    private var nativeAdView: ShelfNativeAdHostingView?
    private var fallbackBannerView: BannerView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    func configure(
        slotID: String,
        layout: ShelfNativeAdLayout,
        nativeAdUnitID: String,
        bannerAdUnitID: String?,
        store: ShelfNativeAdStore
    ) {
        guard configuredSlotID != slotID
                || configuredLayout != layout
                || configuredNativeAdUnitID != nativeAdUnitID
                || configuredBannerAdUnitID != bannerAdUnitID else {
            return
        }

        configuredSlotID = slotID
        configuredLayout = layout
        configuredNativeAdUnitID = nativeAdUnitID
        configuredBannerAdUnitID = bannerAdUnitID
        self.store = store
        adLoader?.delegate = nil
        adLoader = nil
        removeAdContent()

        if let cachedState = cachedState(for: slotID, store: store) {
            show(cachedState: cachedState, layout: layout)
            return
        }

        let mediaOptions = NativeAdMediaAdLoaderOptions()
        mediaOptions.mediaAspectRatio = .square

        let loader = AdLoader(
            adUnitID: nativeAdUnitID,
            rootViewController: self,
            adTypes: [.native],
            options: [mediaOptions]
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    private func cachedState(for slotID: String, store: ShelfNativeAdStore) -> ShelfNativeAdLoadState? {
        switch store.status(for: slotID) {
        case .loaded:
            guard let nativeAd = store.nativeAd(for: slotID) else { return nil }
            return .loaded(nativeAd)
        case .failed:
            return .failed
        case .missing:
            return nil
        }
    }

    private func show(cachedState: ShelfNativeAdLoadState, layout: ShelfNativeAdLayout) {
        switch cachedState {
        case .loaded(let nativeAd):
            show(nativeAd: nativeAd, layout: layout)
        case .failed:
            showFallbackBannerIfAvailable()
        }
    }

    private func show(nativeAd: NativeAd, layout: ShelfNativeAdLayout) {
        removeAdContent()
        nativeAd.delegate = self

        let adView = ShelfNativeAdHostingView(layout: layout)
        adView.translatesAutoresizingMaskIntoConstraints = false
        adView.populate(with: nativeAd)
        view.addSubview(adView)

        NSLayoutConstraint.activate([
            adView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            adView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            adView.topAnchor.constraint(equalTo: view.topAnchor),
            adView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        nativeAdView = adView
    }

    private func showFallbackBannerIfAvailable() {
        removeAdContent()

        guard let bannerAdUnitID = configuredBannerAdUnitID,
              let layout = configuredLayout else { return }

        let bannerSize = inlineAdaptiveBanner(
            width: max(1, floor(layout.contentWidth)),
            maxHeight: ShelfLegacyMetrics.shelfAdInlineMaxHeight
        )
        let bannerView = BannerView(adSize: bannerSize)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adUnitID = bannerAdUnitID
        bannerView.rootViewController = self
        view.addSubview(bannerView)

        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            bannerView.widthAnchor.constraint(equalToConstant: bannerSize.size.width),
            bannerView.heightAnchor.constraint(equalToConstant: bannerSize.size.height)
        ])

        fallbackBannerView = bannerView
        bannerView.load(Request())
    }

    private func removeAdContent() {
        nativeAdView?.nativeAd = nil
        nativeAdView?.removeFromSuperview()
        nativeAdView = nil
        fallbackBannerView?.removeFromSuperview()
        fallbackBannerView = nil
    }

    deinit {
        adLoader?.delegate = nil
        adLoader = nil
    }
}

extension ShelfNativeAdViewController: NativeAdLoaderDelegate, AdLoaderDelegate {
    func adLoader(_ loader: AdLoader, didReceive nativeAd: NativeAd) {
        guard adLoader === loader,
              let slotID = configuredSlotID,
              let layout = configuredLayout,
              let store else { return }

        store.recordLoaded(nativeAd, for: slotID)
        show(nativeAd: nativeAd, layout: layout)
    }

    func adLoader(_ loader: AdLoader, didFailToReceiveAdWithError error: Error) {
        guard adLoader === loader,
              let slotID = configuredSlotID,
              let store else { return }

        store.recordFailure(for: slotID)
        showFallbackBannerIfAvailable()
    }
}

extension ShelfNativeAdViewController: NativeAdDelegate {}

private final class ShelfNativeAdHostingView: NativeAdView {
    private let layout: ShelfNativeAdLayout
    private let mediaAssetView = MediaView()
    private let headlineLabel = UILabel()
    private let bodyLabel = UILabel()
    private let callToActionButton = UIButton(type: .system)
    private let iconImageView = UIImageView()
    private let advertiserLabel = UILabel()
    private let attributionLabel = UILabel()

    init(layout: ShelfNativeAdLayout) {
        self.layout = layout
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        self.layout = .endcap(width: 1)
        super.init(coder: coder)
        setupView()
    }

    func populate(with nativeAd: NativeAd) {
        headlineLabel.text = nativeAd.headline
        mediaAssetView.mediaContent = nativeAd.mediaContent

        bodyLabel.text = nativeAd.body
        bodyLabel.isHidden = nativeAd.body == nil

        callToActionButton.setTitle(nativeAd.callToAction, for: .normal)
        callToActionButton.isHidden = nativeAd.callToAction == nil

        iconImageView.image = nativeAd.icon?.image
        iconImageView.isHidden = nativeAd.icon == nil

        advertiserLabel.text = nativeAd.advertiser
        advertiserLabel.isHidden = nativeAd.advertiser == nil

        self.nativeAd = nativeAd
    }

    private func setupView() {
        backgroundColor = UIColor.systemBackground
        layer.cornerRadius = 8
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1
        clipsToBounds = true

        let isStrip: Bool
        switch layout {
        case .endcap:
            isStrip = false
        case .strip:
            isStrip = true
        }

        headlineLabel.font = .preferredFont(forTextStyle: .subheadline)
        headlineLabel.numberOfLines = isStrip ? 1 : 2
        headlineLabel.adjustsFontForContentSizeCategory = true

        bodyLabel.font = .preferredFont(forTextStyle: .caption1)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        bodyLabel.adjustsFontForContentSizeCategory = true

        advertiserLabel.font = .preferredFont(forTextStyle: .caption2)
        advertiserLabel.textColor = .secondaryLabel
        advertiserLabel.numberOfLines = 1
        advertiserLabel.adjustsFontForContentSizeCategory = true

        attributionLabel.text = "Ad"
        attributionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        attributionLabel.textColor = .label
        attributionLabel.textAlignment = .center
        attributionLabel.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.9)
        attributionLabel.layer.cornerRadius = 3
        attributionLabel.clipsToBounds = true

        iconImageView.contentMode = .scaleAspectFill
        iconImageView.layer.cornerRadius = 6
        iconImageView.clipsToBounds = true

        callToActionButton.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        callToActionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        callToActionButton.backgroundColor = tintColor
        callToActionButton.tintColor = .white
        callToActionButton.layer.cornerRadius = 6
        callToActionButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        callToActionButton.isUserInteractionEnabled = false

        [mediaAssetView, headlineLabel, bodyLabel, callToActionButton, iconImageView, advertiserLabel, attributionLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        mediaView = mediaAssetView
        headlineView = headlineLabel
        bodyView = bodyLabel
        callToActionView = callToActionButton
        iconView = iconImageView
        advertiserView = advertiserLabel

        switch layout {
        case .endcap:
            activateEndcapConstraints()
        case .strip:
            activateStripConstraints()
        }
    }

    private func activateEndcapConstraints() {
        NSLayoutConstraint.activate([
            attributionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            attributionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            attributionLabel.widthAnchor.constraint(equalToConstant: 28),
            attributionLabel.heightAnchor.constraint(equalToConstant: 18),

            mediaAssetView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            mediaAssetView.topAnchor.constraint(equalTo: attributionLabel.bottomAnchor, constant: 8),
            mediaAssetView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            mediaAssetView.widthAnchor.constraint(equalToConstant: 120),
            mediaAssetView.heightAnchor.constraint(equalToConstant: 120),

            iconImageView.leadingAnchor.constraint(equalTo: mediaAssetView.trailingAnchor, constant: 10),
            iconImageView.topAnchor.constraint(equalTo: mediaAssetView.topAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 34),
            iconImageView.heightAnchor.constraint(equalToConstant: 34),

            headlineLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            headlineLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
            headlineLabel.topAnchor.constraint(equalTo: iconImageView.topAnchor),

            advertiserLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            advertiserLabel.trailingAnchor.constraint(equalTo: headlineLabel.trailingAnchor),
            advertiserLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 2),

            bodyLabel.leadingAnchor.constraint(equalTo: mediaAssetView.trailingAnchor, constant: 10),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bodyLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),

            callToActionButton.leadingAnchor.constraint(equalTo: bodyLabel.leadingAnchor),
            callToActionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            callToActionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            callToActionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: callToActionButton.topAnchor, constant: -6)
        ])
    }

    private func activateStripConstraints() {
        NSLayoutConstraint.activate([
            attributionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            attributionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            attributionLabel.widthAnchor.constraint(equalToConstant: 28),
            attributionLabel.heightAnchor.constraint(equalToConstant: 18),

            mediaAssetView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            mediaAssetView.centerYAnchor.constraint(equalTo: centerYAnchor),
            mediaAssetView.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            mediaAssetView.widthAnchor.constraint(equalToConstant: 136),
            mediaAssetView.heightAnchor.constraint(equalTo: mediaAssetView.widthAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: mediaAssetView.trailingAnchor, constant: 18),
            iconImageView.topAnchor.constraint(equalTo: mediaAssetView.topAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 42),
            iconImageView.heightAnchor.constraint(equalToConstant: 42),

            headlineLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 10),
            headlineLabel.trailingAnchor.constraint(equalTo: callToActionButton.leadingAnchor, constant: -16),
            headlineLabel.topAnchor.constraint(equalTo: iconImageView.topAnchor),

            advertiserLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            advertiserLabel.trailingAnchor.constraint(equalTo: headlineLabel.trailingAnchor),
            advertiserLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 3),

            bodyLabel.leadingAnchor.constraint(equalTo: iconImageView.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: callToActionButton.leadingAnchor, constant: -16),
            bodyLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),

            callToActionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            callToActionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            callToActionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            callToActionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
    }
}
#endif

struct ShelfNativeAd: View {
    enum Layout {
        case endcap(width: CGFloat)
        case strip(width: CGFloat)

        fileprivate var nativeLayout: ShelfNativeAdLayout {
            switch self {
            case .endcap(let width):
                return .endcap(width: width)
            case .strip(let width):
                return .strip(width: width)
            }
        }

        var frameSize: CGSize {
            switch self {
            case .endcap(let width):
                return CGSize(width: width, height: ShelfLegacyMetrics.tileHeight)
            case .strip(let width):
                return CGSize(width: width, height: ShelfLegacyMetrics.shelfNativeStripRowHeight)
            }
        }
    }

    let slotID: String
    let layout: Layout
    let store: ShelfNativeAdStore

    var body: some View {
        #if canImport(GoogleMobileAds) && GAD_ENABLED
        if let nativeAdUnitID = YabrAppInfo.shared.gadNativeShelfUnitID {
            let frameSize = layout.frameSize
            ShelfNativeAdVC(
                slotID: slotID,
                layout: layout.nativeLayout,
                nativeAdUnitID: nativeAdUnitID,
                bannerAdUnitID: YabrAppInfo.shared.gadBannerShelfUnitID,
                store: store
            )
            .frame(width: frameSize.width, height: frameSize.height, alignment: .center)
        } else {
            let frameSize = layout.frameSize
            AdaptiveBanner(
                width: max(1, frameSize.width),
                maxHeight: ShelfLegacyMetrics.shelfAdInlineMaxHeight
            )
            .frame(width: frameSize.width, height: frameSize.height, alignment: .center)
        }
        #else
        EmptyView()
        #endif
    }
}

struct ShelfAdSlot: View {
    enum Placement {
        case adaptiveBanner(width: CGFloat, columnCount: Int, tileWidth: CGFloat, slotID: String)
        case nativeEndcap(width: CGFloat, slotID: String)
        case nativeStrip(width: CGFloat, slotID: String)
    }

    let placement: Placement
    let store: ShelfNativeAdStore

    static var isNativeAvailable: Bool {
        #if canImport(GoogleMobileAds) && GAD_ENABLED
        return YabrAppInfo.shared.gadNativeShelfUnitID != nil
        #else
        return false
        #endif
    }

    static var isBannerAvailable: Bool {
        #if canImport(GoogleMobileAds) && GAD_ENABLED
        return YabrAppInfo.shared.gadBannerShelfUnitID != nil
        #else
        return false
        #endif
    }

    static var isInlineAvailable: Bool {
        isNativeAvailable || isBannerAvailable
    }

    var body: some View {
        #if canImport(GoogleMobileAds) && GAD_ENABLED
        switch placement {
        case .adaptiveBanner(let width, let columnCount, let tileWidth, _):
            ZStack {
                HStack(spacing: 0) {
                    ForEach(0..<max(1, columnCount), id: \.self) { index in
                        ShelfLegacyFillerTile(
                            kind: ShelfLegacyLayout.tileKind(index: index, columnCount: max(1, columnCount)),
                            width: tileWidth
                        )
                    }
                }
                .frame(height: ShelfLegacyMetrics.shelfAdInlineRowHeight, alignment: .bottom)
                .clipped()

                AdaptiveBanner(
                    width: max(1, width - 48),
                    maxHeight: ShelfLegacyMetrics.shelfAdInlineMaxHeight
                )
                .padding(.horizontal, 24)
                .accessibilityLabel("Advertisement")
            }
            .frame(width: width, height: ShelfLegacyMetrics.shelfAdInlineRowHeight)
        case .nativeEndcap(let width, let slotID):
            ShelfNativeAd(slotID: slotID, layout: .endcap(width: width), store: store)
                .accessibilityLabel("Advertisement")
        case .nativeStrip(let width, let slotID):
            ShelfNativeAd(
                slotID: slotID,
                layout: .strip(width: max(1, width - 56)),
                store: store
            )
                .padding(.horizontal, 28)
                .frame(width: width, height: ShelfLegacyMetrics.shelfNativeStripRowHeight)
                .accessibilityLabel("Advertisement")
        }
        #else
        EmptyView()
        #endif
    }
}

struct Banner_Previews: PreviewProvider {
    static private var container = AppContainer()

    static var previews: some View {
        Banner()
            .environment(\.appContainer, container)
    }
}
