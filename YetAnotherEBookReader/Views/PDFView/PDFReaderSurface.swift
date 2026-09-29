//
//  PDFReaderSurface.swift
//  YetAnotherEBookReader
//

import PDFKit
import UIKit

extension Notification.Name {
    /// The active page view's `PDFViewPageChanged`, relayed with the surface as object.
    static let readerSurfacePageChanged = Notification.Name("YabrPDFReaderSurfacePageChanged")
    /// The active page view's `PDFViewScaleChanged`, relayed with the surface as object.
    static let readerSurfaceScaleChanged = Notification.Name("YabrPDFReaderSurfaceScaleChanged")
    /// The active page view's `PDFViewDisplayBoxChanged`, relayed with the surface as object.
    static let readerSurfaceDisplayBoxChanged = Notification.Name("YabrPDFReaderSurfaceDisplayBoxChanged")
}

/// Hosts the reader's page views and owns what they share. It holds one page view
/// today; buffered neighbour pages are planned (issues #54 / #55), after which the
/// active view can change.
///
/// Read `activeView` at the point of use and never keep a reference to it, and
/// observe the surface's notifications rather than a page view's.
@available(iOS 16.0, macCatalyst 16.0, *)
final class PDFReaderSurface: UIView {
    private(set) var activeView = YabrPDFView()

    private var relayObservers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        install(activeView)
        relayNotifications(of: activeView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        relayObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func install(_ pageView: YabrPDFView) {
        pageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: topAnchor),
            pageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageView.leftAnchor.constraint(equalTo: leftAnchor),
            pageView.rightAnchor.constraint(equalTo: rightAnchor),
        ])
    }

    private func relayNotifications(of pageView: YabrPDFView) {
        let relays: [(Notification.Name, Notification.Name)] = [
            (.PDFViewPageChanged, .readerSurfacePageChanged),
            (.PDFViewScaleChanged, .readerSurfaceScaleChanged),
            (.PDFViewDisplayBoxChanged, .readerSurfaceDisplayBoxChanged),
        ]
        relayObservers = relays.map { source, relayed in
            // No queue: delivered synchronously, as PDFKit posts them.
            NotificationCenter.default.addObserver(forName: source, object: pageView, queue: nil) { [weak self] _ in
                guard let self else { return }
                NotificationCenter.default.post(name: relayed, object: self)
            }
        }
    }
}
