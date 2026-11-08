import SwiftUI
import WebKit

struct BookDescriptionSection: View {
    let document: BookDescriptionDocument
    let scrollToHeading: () -> Void
    @ScaledMetric(relativeTo: .body) private var textSize = 17.0
    @ScaledMetric(relativeTo: .body) private var collapsedHeight = 180.0
    @Environment(\.openURL) private var openURL
    @State private var measurement: Measurement?
    @State private var isExpanded = false

    private struct Measurement: Equatable {
        let document: BookDescriptionDocument
        let height: CGFloat
    }

    var body: some View {
        let height = measurement?.document == document ? measurement?.height : nil
        let isLong = (height ?? 0) > collapsedHeight
        let isClipped = isLong && !isExpanded
        BookDetailSection("Description") {
            BookDescriptionWebView(document: document, textSize: textSize,
                openLink: { openURL($0) },
                onHeight: { measuredDocument, height in
                    let next = Measurement(document: measuredDocument, height: height)
                    if measurement != next { measurement = next }
                },
                revealAnchor: { offset in
                    if offset >= collapsedHeight { isExpanded = true }
                })
                .frame(height: max(1, isClipped ? collapsedHeight : height ?? 1))
                .overlay(alignment: .bottom) {
                    if isClipped {
                        LinearGradient(colors: [.clear, Color(uiColor: .secondarySystemGroupedBackground)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                            .allowsHitTesting(false)
                    }
                }
            if isLong {
                Button(isExpanded ? "Show Less" : "Show More") {
                    if isExpanded { scrollToHeading() }
                    isExpanded.toggle()
                }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("book-description.toggle")
            }
        }
        // Keep the measuring view mounted for markup-only descriptions, so a late image can appear.
        .frame(height: height == 0 ? 0 : nil)
        .clipped()
        .opacity(height == 0 ? 0 : 1)
        .accessibilityHidden(height == 0)
        .onChange(of: document) { _ in isExpanded = false }
    }
}

struct BookDescriptionDocument: Equatable {
    let html: String
    let baseURL: URL?

    var hasMarkup: Bool {
        let content = html.trimmingCharacters(in: .whitespacesAndNewlines)
        return !content.isEmpty && content != "Without Comments"
    }

    func page(token: String, textSize: CGFloat) -> String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="yabr-description" content="\(token)">
        <style>
        :root { color-scheme: light dark; font-size: var(--yabr-text-size, \(textSize)px); }
        html { overflow-x: hidden; -webkit-text-size-adjust: none; }
        body { display: flow-root; margin: 0; font-family: -apple-system, sans-serif;
               line-height: 1.45; overflow-wrap: anywhere; }
        img, video { max-width: 100% !important; height: auto !important; }
        svg, iframe, table { max-width: 100%; }
        pre { white-space: pre-wrap; }
        a:link { color: #005ea7; }
        a:visited { color: #623d8d; }
        @media (prefers-color-scheme: dark) {
            a:link { color: #72bbff; }
            a:visited { color: #c9a6ff; }
        }
        </style></head>
        \(html)
        """
    }
}

struct BookDescriptionWebView: UIViewRepresentable {
    let document: BookDescriptionDocument
    let textSize: CGFloat
    let openLink: (URL) -> Void
    let onHeight: (BookDescriptionDocument, CGFloat) -> Void
    let revealAnchor: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> InlineWebView {
        context.coordinator.makeWebView()
    }

    func updateUIView(_ webView: InlineWebView, context: Context) {
        context.coordinator.update(self, in: webView)
    }

    static func dismantleUIView(_ webView: InlineWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "description", contentWorld: .defaultClient)
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private var document: BookDescriptionDocument?
        private var token = ""
        private var textSize: CGFloat = 0
        private var navigation: WKNavigation?
        private var openLink: ((URL) -> Void)?
        private var onHeight: ((BookDescriptionDocument, CGFloat) -> Void)?
        private var revealAnchor: ((CGFloat) -> Void)?

        func makeWebView() -> InlineWebView {
            let configuration = WKWebViewConfiguration()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.defaultWebpagePreferences.preferredContentMode = .mobile
            let controller = configuration.userContentController
            controller.add(self, contentWorld: .defaultClient, name: "description")
            controller.addUserScript(WKUserScript(source: BookDescriptionWebView.measurementScript, injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true, in: .defaultClient))
            let webView = InlineWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            return webView
        }

        func update(_ view: BookDescriptionWebView, in webView: InlineWebView) {
            openLink = view.openLink
            onHeight = view.onHeight
            revealAnchor = view.revealAnchor
            let fontChanged = textSize != view.textSize
            textSize = view.textSize
            if document != view.document {
                document = view.document
                token = UUID().uuidString
                webView.anchorOffset = nil
                navigation = webView.loadHTMLString(view.document.page(token: token, textSize: textSize),
                                                    baseURL: view.document.baseURL)
            } else if fontChanged {
                applyTextSize(to: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === self.navigation else { return }
            // A font change can arrive while the new document is still provisional.
            applyTextSize(to: webView)
        }

        private func applyTextSize(to webView: WKWebView) {
            // Use the original WebKit method so Release can launch on runtimes without
            // libswiftWebKit. Only the generated token and the system font size enter the script.
            webView.evaluateJavaScript("""
                if (document.querySelector('meta[name="yabr-description"]')?.content === '\(token)')
                    document.documentElement.style.setProperty('--yabr-text-size', '\(textSize)px');
                """, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let report = message.body as? [String: Any], report["token"] as? String == token,
                  let document else { return }
            if let height = report["height"] as? CGFloat, height.isFinite, height >= 0 {
                onHeight?(document, height)
            }
            if let offset = report["anchor"] as? CGFloat, offset.isFinite, offset >= 0,
               let webView = message.webView as? InlineWebView {
                revealAnchor?(offset)
                webView.anchorOffset = offset
                webView.setNeedsLayout()
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                decisionHandler(.cancel)
                if let url = action.request.url, let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto", "tel"].contains(scheme) {
                    openLink?(url)
                }
                return
            }
            // The document comes from loadHTMLString. Keep redirects and form submissions out
            // of the embedded view so its height always belongs to the description.
            let url = action.request.url
            decisionHandler(action.navigationType == .other &&
                (action.targetFrame?.isMainFrame == false || url == document?.baseURL || url?.absoluteString == "about:blank")
                ? .allow : .cancel)
        }
    }

    final class InlineWebView: WKWebView {
        var anchorOffset: CGFloat?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let anchorOffset, anchorOffset < bounds.height else { return }
            self.anchorOffset = nil
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                    let target = CGRect(x: 0, y: anchorOffset, width: 1, height: 24)
                    scroll.scrollRectToVisible(convert(target, to: scroll), animated: true)
                    return
                }
                ancestor = view.superview
            }
        }
    }

    private static let measurementScript = """
        const token = document.querySelector('meta[name="yabr-description"]')?.content;
        if (token && document.body) {
            const post = value => window.webkit.messageHandlers.description.postMessage({token, ...value});
            const body = document.body;
            let lastHeight, width = document.documentElement.clientWidth;
            const report = () => {
                const hasContent = body.innerText.trim() ||
                    body.querySelector('img,svg,video,audio,iframe,canvas,object,embed,hr');
                const height = hasContent ? Math.ceil(body.getBoundingClientRect().height) : 0;
                if (height !== lastHeight) {
                    lastHeight = height;
                    post({height});
                }
            };
            new MutationObserver(report).observe(document.documentElement, {
                attributes: true, attributeFilter: ['style']
            });
            // A details element's toggle event does not bubble.
            document.addEventListener('toggle', report, true);
            // The native viewport height is an output. Measuring again on height-only changes
            // would let a description using vh units grow every time the native view grows.
            window.addEventListener('resize', () => {
                const nextWidth = document.documentElement.clientWidth;
                if (nextWidth !== width) {
                    width = nextWidth;
                    report();
                }
            });
            document.addEventListener('load', report, true);
            window.addEventListener('load', report);
            document.fonts.addEventListener('loadingdone', report);
            report();
            document.addEventListener('click', event => {
                const href = event.target.closest('a[href]')?.getAttribute('href');
                if (!href?.startsWith('#')) return;
                event.preventDefault();
                let name;
                try { name = decodeURIComponent(href.slice(1)); } catch { return; }
                const target = document.getElementById(name) || document.getElementsByName(name)[0];
                if (target || !name)
                    post({anchor: target ? Math.max(0, target.getBoundingClientRect().top + window.scrollY) : 0});
            });
        }
        """
}
