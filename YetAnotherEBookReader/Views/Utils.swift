//
//  Utils.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/4.
//

import SwiftUI
import Foundation

struct AlertItem : Identifiable, Equatable {
    static func == (lhs: AlertItem, rhs: AlertItem) -> Bool {
        lhs.id == rhs.id
    }

    var id: String
    var msg: String?
    var action: (() -> Void)?
}

protocol AlertDelegate {
    func alert(alertItem: AlertItem)
    func alert(msg: String)
}

extension AlertDelegate {
    func alert(msg: String) {
        self.alert(
            alertItem: AlertItem(
                id: "Alert",
                msg: msg
            )
        )
    }
}

extension UIApplication {

    var keyWindow: UIWindow? {
        // Get connected scenes
        return UIApplication.shared.connectedScenes
            // Keep only active scenes, onscreen and visible to the user
            .filter { $0.activationState == .foregroundActive }
            // Keep only the first `UIWindowScene`
            .first(where: { $0 is UIWindowScene })
            // Get its associated windows
            .flatMap({ $0 as? UIWindowScene })?.windows
            // Finally, keep only the key window
            .first(where: \.isKeyWindow)
    }

}

internal extension UIColor {
    //
    /// Hex string of a UIColor instance.
    ///
    /// from: https://github.com/yeahdongcn/UIColor-Hex-Swift
    ///
    /// - Parameter includeAlpha: Whether the alpha should be included.
    /// - Returns: Hexa string
    func hexString(_ includeAlpha: Bool) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        self.getRed(&r, green: &g, blue: &b, alpha: &a)

        if (includeAlpha == true) {
            return String(format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
        } else {
            return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }
    }
}


extension URL {
    public var isHTTP: Bool {
        ["http", "https"].contains(scheme?.lowercased())
    }
}

struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

enum YabrAppChromeStyle {
    case wood
    case system

    func applyAsDefaultAppearance() {
        let navigationAppearance = makeNavigationBarAppearance()
        let tabAppearance = makeTabBarAppearance()

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    fileprivate func makeNavigationBarAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()

        switch self {
        case .wood:
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(ShelfLegacyMetrics.shelfBackgroundColor)
            appearance.shadowColor = .clear
            appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]
        case .system:
            appearance.configureWithDefaultBackground()
        }

        return appearance
    }

    fileprivate func makeTabBarAppearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()

        switch self {
        case .wood:
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(ShelfLegacyMetrics.shelfBackgroundColor)
            appearance.shadowColor = .clear

            let normalTextAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.black.withAlphaComponent(0.6)]
            let selectedTextAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.systemBlue]
            let normalIconColor = UIColor.black.withAlphaComponent(0.5)
            let selectedIconColor = UIColor.systemBlue

            for layoutAppearance in [
                appearance.stackedLayoutAppearance,
                appearance.inlineLayoutAppearance,
                appearance.compactInlineLayoutAppearance
            ] {
                layoutAppearance.normal.iconColor = normalIconColor
                layoutAppearance.normal.titleTextAttributes = normalTextAttributes
                layoutAppearance.selected.iconColor = selectedIconColor
                layoutAppearance.selected.titleTextAttributes = selectedTextAttributes
            }
        case .system:
            appearance.configureWithDefaultBackground()
        }

        return appearance
    }

    fileprivate func applyToSelectedTab(containing viewController: UIViewController) {
        guard let tabBarController = nearestTabBarController(from: viewController),
              let selectedViewController = tabBarController.selectedViewController,
              contains(viewController, in: selectedViewController)
        else {
            return
        }

        let navigationAppearance = makeNavigationBarAppearance()
        let tabAppearance = makeTabBarAppearance()

        apply(to: tabBarController.tabBar, appearance: tabAppearance)

        var visited = Set<ObjectIdentifier>()
        applyNavigationBars(
            in: selectedViewController,
            appearance: navigationAppearance,
            visited: &visited
        )
    }

    private func nearestTabBarController(from viewController: UIViewController) -> UITabBarController? {
        var current: UIViewController? = viewController

        while let controller = current {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }

            if let tabBarController = controller.tabBarController {
                return tabBarController
            }

            current = controller.parent
        }

        return nil
    }

    private func contains(_ target: UIViewController, in root: UIViewController) -> Bool {
        if root === target {
            return true
        }

        for child in root.children {
            if contains(target, in: child) {
                return true
            }
        }

        return false
    }

    private func applyNavigationBars(
        in viewController: UIViewController,
        appearance: UINavigationBarAppearance,
        visited: inout Set<ObjectIdentifier>
    ) {
        let identifier = ObjectIdentifier(viewController)
        guard visited.insert(identifier).inserted else { return }

        if let navigationController = viewController as? UINavigationController {
            apply(to: navigationController.navigationBar, appearance: appearance)
        } else if let navigationBar = viewController.navigationController?.navigationBar {
            apply(to: navigationBar, appearance: appearance)
        }

        for child in viewController.children {
            applyNavigationBars(in: child, appearance: appearance, visited: &visited)
        }
    }

    private func apply(to navigationBar: UINavigationBar, appearance: UINavigationBarAppearance) {
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.setNeedsLayout()
    }

    private func apply(to tabBar: UITabBar, appearance: UITabBarAppearance) {
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.setNeedsLayout()
    }
}

private struct YabrAppChromeAppearanceModifier: ViewModifier {
    let style: YabrAppChromeStyle
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background(YabrAppChromeAppearanceApplicator(style: style, isActive: isActive).frame(width: 0, height: 0))
    }
}

private struct YabrAppChromeAppearanceApplicator: UIViewControllerRepresentable {
    let style: YabrAppChromeStyle
    let isActive: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller(style: style, isActive: isActive)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.style = style
        uiViewController.isActive = isActive
        uiViewController.applyStyle()
    }

    final class Controller: UIViewController {
        var style: YabrAppChromeStyle
        var isActive: Bool

        init(style: YabrAppChromeStyle, isActive: Bool) {
            self.style = style
            self.isActive = isActive
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyStyle()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyStyle()
        }

        func applyStyle() {
            guard isActive else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isActive else { return }
                self.style.applyToSelectedTab(containing: self)
            }
        }
    }
}

extension View {
    func yabrAppChrome(_ style: YabrAppChromeStyle, isActive: Bool = true) -> some View {
        modifier(YabrAppChromeAppearanceModifier(style: style, isActive: isActive))
    }
}
