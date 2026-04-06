//
//  YabrReadiumEPUBViewController.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/5/29.
//

import Foundation
import UIKit
import SwiftUI
import RealmSwift
import ReadiumShared
import ReadiumNavigator
import AVFoundation
import MediaPlayer
import WebKit

import ReadiumAdapterGCDWebServer

class YabrReadiumEPUBViewController: YabrReadiumReaderViewController {

    private var preferences = EPUBPreferences()

    init?(publication: Publication, initialLocation: Locator?, environment: YabrReadiumEnvironment) {
        // Set contentInset to zero to allow additionalSafeAreaInsets to fully control margins
        var config = EPUBNavigatorViewController.Configuration()
        config.contentInset = [
            .compact: (top: 0, bottom: 0),
            .regular: (top: 0, bottom: 0)
        ]
        
        guard let navigator = try? EPUBNavigatorViewController(
            publication: publication,
            initialLocation: initialLocation,
            config: config
        ) else {
            return nil
        }

        super.init(navigator: navigator, publication: publication, initialLocation: initialLocation, environment: environment)

        navigator.delegate = self
    }
    
    var epubNavigator: EPUBNavigatorViewController {
        return navigator as! EPUBNavigatorViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    private func getVerticalScrollViews(from view: UIView, into list: inout [WKWebView]) {
        if let webView = view as? WKWebView {
            list.append(webView)
        }
        for subview in view.subviews {
            getVerticalScrollViews(from: subview, into: &list)
        }
    }
    
    private func getActiveVerticalScrollView() -> UIScrollView? {
        var webViews = [WKWebView]()
        getVerticalScrollViews(from: self.navigator.view, into: &webViews)
        
        if webViews.isEmpty { return nil }
        if webViews.count == 1 { return webViews[0].scrollView }
        
        // If multiple exist (e.g. during transition), find the one most central to the container
        let containerBounds = self.navigator.view.bounds
        let containerCenter = CGPoint(x: containerBounds.midX, y: containerBounds.midY)
        
        return webViews.sorted { (wv1, wv2) -> Bool in
            let frame1 = wv1.convert(wv1.bounds, to: self.navigator.view)
            let frame2 = wv2.convert(wv2.bounds, to: self.navigator.view)
            let dist1 = pow(frame1.midX - containerCenter.x, 2) + pow(frame1.midY - containerCenter.y, 2)
            let dist2 = pow(frame2.midX - containerCenter.x, 2) + pow(frame2.midY - containerCenter.y, 2)
            return dist1 < dist2
        }.first?.scrollView
    }
    
    override func handleVolumeKey(up: Bool) {
        let isScroll = self.preferences.scroll ?? false
        let isRTL = self.preferences.readingProgression == .rtl
        
        if isScroll {
            guard let scrollView = getActiveVerticalScrollView() else {
                self.log(.debug, "No active scroll view found, falling back to jump")
                Task {
                    if up { await self.epubNavigator.goBackward(options: .animated) }
                    else { await self.epubNavigator.goForward(options: .animated) }
                }
                return
            }
            
            let offset = scrollView.contentOffset
            let viewHeight = scrollView.bounds.height
            let contentHeight = scrollView.contentSize.height
            let scrollAmount = max(0, viewHeight - 80)
            
            if up {
                if offset.y <= 0 {
                    self.log(.debug, "At top, jumping backward")
                    Task { await self.epubNavigator.goBackward(options: .animated) }
                } else {
                    let newY = max(0, offset.y - scrollAmount)
                    self.log(.debug, "Scrolling up to \(newY)")
                    scrollView.setContentOffset(CGPoint(x: offset.x, y: newY), animated: true)
                }
            } else {
                let maxOffsetY = max(0, contentHeight - viewHeight)
                if offset.y >= maxOffsetY - 1 { // 1pt tolerance
                    self.log(.debug, "At bottom, jumping forward")
                    Task { await self.epubNavigator.goForward(options: .animated) }
                } else {
                    let newY = min(maxOffsetY, offset.y + scrollAmount)
                    self.log(.debug, "Scrolling down to \(newY)")
                    scrollView.setContentOffset(CGPoint(x: offset.x, y: newY), animated: true)
                }
            }
        } else {
            super.handleVolumeKey(up: up)
        }
    }
    
    override func applyPreferences(_ prefs: ReadiumPreferenceRealm) {
        self.preferences = prefs.toEPUBPreferences()
        epubNavigator.submitPreferences(self.preferences)
    }
    
    override func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        // If isScroll is nil (PDF usually), we return nil to fallback to base behavior
        // But since this is EPUB, we check our specific scroll preference.
        if self.preferences.scroll ?? false {
            return nil
        }
        
        let safeArea = self.view.window?.safeAreaInsets ?? self.view.safeAreaInsets
        let additional = self.navigator.additionalSafeAreaInsets
        
        let inset = UIEdgeInsets(
            top: safeArea.top + additional.top,
            left: safeArea.left + additional.left,
            bottom: safeArea.bottom + additional.bottom,
            right: safeArea.right + additional.right
        )
        self.log(.debug, "navigatorContentInset called, additionalTop=\(additional.top), returning: \(inset)")
        return inset
    }
}

extension YabrReadiumEPUBViewController: EPUBNavigatorDelegate {
    
}

extension YabrReadiumEPUBViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
}
