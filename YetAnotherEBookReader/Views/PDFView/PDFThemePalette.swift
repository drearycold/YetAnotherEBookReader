//
//  PDFThemePalette.swift
//  YetAnotherEBookReader
//

import CoreGraphics
import UIKit

/// How a YabrPDF theme is rendered.
///
/// iOS ignores `CALayer.compositingFilter`, so blend-mode overlays are not
/// available. Light tints (sepia, forest) use a plain alpha overlay above the
/// PDFView, solved so that white composites to exactly `background`; this also
/// tints PDFKit's white placeholder before page tiles finish rendering. Dark needs
/// inversion, which an alpha overlay cannot do, so it stays in `PDFPage.draw`.
struct PDFThemePalette: Equatable {
    struct Overlay: Equatable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat

        /// Normal "source over" compositing of this overlay onto `color`.
        func composite(over color: (red: CGFloat, green: CGFloat, blue: CGFloat)) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
            (
                alpha * red + (1 - alpha) * color.red,
                alpha * green + (1 - alpha) * color.green,
                alpha * blue + (1 - alpha) * color.blue
            )
        }
    }

    let themeMode: PDFThemeMode
    /// Chrome, list and page background colour, in sRGB: `CGColor(red:green:blue:)`
    /// is Generic RGB (gamma 1.8) and renders visibly lighter than the page.
    let background: CGColor
    /// Colour of the PDFView canvas outside the page, below the overlay.
    let canvas: CGColor
    /// Alpha overlay for light tints, `nil` when none is needed.
    let overlay: Overlay?
    /// Pages are drawn inverted by `PDFPageWithBackground.draw` (dark theme).
    let drawsInverted: Bool

    init(themeMode: PDFThemeMode) {
        self.themeMode = themeMode
        switch themeMode {
        case .none:
            background = CGColor(gray: 0.0, alpha: 0.0)
            canvas = background
            overlay = nil
            drawsInverted = false
        case .serpia:
            background = CGColor(srgbRed: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
            canvas = CGColor(gray: 1.0, alpha: 1.0)
            overlay = Self.overlay(mappingWhiteTo: background)
            drawsInverted = false
        case .forest:
            background = CGColor(srgbRed: 0xBA / 255.0, green: 0xD5 / 255.0, blue: 0xC1 / 255.0, alpha: 1.0)
            canvas = CGColor(gray: 1.0, alpha: 1.0)
            overlay = Self.overlay(mappingWhiteTo: background)
            drawsInverted = false
        case .dark:
            background = CGColor(gray: 0.0, alpha: 1.0)
            canvas = background
            overlay = nil
            drawsInverted = true
        }
    }

    /// The lightest overlay that turns white into `target`: alpha is set by the
    /// channel that must drop the most, which keeps black as dark as possible.
    static func overlay(mappingWhiteTo target: CGColor) -> Overlay? {
        guard let components = target.components, components.count >= 3 else { return nil }
        let drop = components.prefix(3).map { 1 - $0 }
        guard let alpha = drop.max(), alpha > 0 else { return nil }
        return Overlay(
            red: 1 - drop[0] / alpha,
            green: 1 - drop[1] / alpha,
            blue: 1 - drop[2] / alpha,
            alpha: alpha
        )
    }
}

extension PDFThemePalette {
    /// Nav bar look for the reader and the sheets it presents. Applied through
    /// `UINavigationItem` so it wins over the app-wide wood appearance that is set
    /// on `UINavigationBar.appearance()` and on individual bars.
    func navigationBarAppearance() -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        if background.alpha > 0 {
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(cgColor: background)
            appearance.shadowColor = .clear
        } else {
            appearance.configureWithDefaultBackground()
        }
        let titleColor: UIColor = drawsInverted ? .white : .black
        appearance.titleTextAttributes = [.foregroundColor: titleColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: titleColor]
        return appearance
    }

    /// The surface of sheets over the page. The dark page is black, so dark
    /// sheets use the raised system surface, or they would merge with it.
    var sheetBackground: UIColor {
        if drawsInverted {
            return UIColor.secondarySystemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        }
        return background.alpha > 0 ? UIColor(cgColor: background) : .systemBackground
    }

    /// The nav bar of a sheet, on `sheetBackground`.
    func applySheet(to navigationItem: UINavigationItem) {
        let appearance = navigationBarAppearance()
        if background.alpha > 0 {
            appearance.backgroundColor = sheetBackground
        }
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
    }

    /// Bar button tint, matching the reader chrome.
    var barTintColor: UIColor {
        drawsInverted ? .lightText : .darkText
    }

    func apply(to navigationItem: UINavigationItem) {
        let appearance = navigationBarAppearance()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance
    }

    func apply(to navigationBar: UINavigationBar) {
        navigationBar.tintColor = barTintColor
    }
}
