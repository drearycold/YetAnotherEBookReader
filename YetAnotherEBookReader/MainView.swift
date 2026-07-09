//
//  MainView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI
import AppTrackingTransparency

#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform
#endif

@available(macCatalyst 14.0, *)
struct MainView: View {
    @Environment(\.appContainer) var container
    @Environment(\.openURL) var openURL
    @Environment(\.horizontalSizeClass) var originalSizeClass

    @ObservedObject var viewModel: MainViewModel

    init(container: AppContainer, viewModel: MainViewModel) {
        self.viewModel = viewModel
    }

    private let issueURL = "https://github.com/drearycold/YetAnotherEBookReader/issues/new?labels=bug&assignees=drearycold"

    var body: some View {
        ZStack {
            if container.databaseService.realmConf != nil {
                TabView(selection: $viewModel.activeTab) {
                    RecentShelfView(viewModel: viewModel.recentShelfViewModel)
                        .environment(\.horizontalSizeClass, originalSizeClass)
                        .yabrAppChrome(.wood, isActive: viewModel.activeTab == 0)
                        .tabItem {
                            Image(systemName: "doc.text.fill")
                            Text("Recent")
                        }
                        .tag(0)
                        .onAppear {
                            container.publishCalibreUpdate(.shelf)
                        }

                    SectionShelfView(viewModel: viewModel.sectionShelfViewModel)
                        .environment(\.horizontalSizeClass, originalSizeClass)
                        .yabrAppChrome(.wood, isActive: viewModel.activeTab == 1)
                        .tabItem {
                            Image(systemName: "books.vertical.fill")
                            Text("Discover")
                        }
                        .tag(1)

                    LibraryInfoView()
                        .environment(\.horizontalSizeClass, originalSizeClass)
                        .yabrAppChrome(.system, isActive: viewModel.activeTab == 2)
                        .tabItem {
                            Image(systemName: "building.columns.fill")
                            Text("Browse")
                        }
                        .tag(2)

                    NavigationView {
                        SettingsView(viewModel: viewModel.settingsViewModel)
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .environment(\.horizontalSizeClass, originalSizeClass)
                    .yabrAppChrome(.system, isActive: viewModel.activeTab == 3)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .tag(3)
                }
                .environment(\.horizontalSizeClass, .compact)
            } else {
                Color.clear
            }

            if viewModel.showWelcome {
                WelcomeEmptyShelfView(
                    openSettings: viewModel.openWelcomeSettings,
                    openBrowse: viewModel.openWelcomeBrowse
                )
            }

            if viewModel.readerWorkspaceViewModel.hasReaders {
                ReaderWorkspaceView(viewModel: viewModel.readerWorkspaceViewModel)
                    .zIndex(10)
            }
        }
        .alert(item: $viewModel.alertItem) { item in
            if item.id == "ForwardProgress" || item.id == "BackwardProgress" {
                return Alert(
                    title: Text("Confirm New Progress"),
                    message: Text(item.msg ?? ""),
                    primaryButton: .destructive(Text("Confirm")) {
                        viewModel.updateCurrentPosition()
                    },
                    secondaryButton: .cancel()
                )
            }
            if item.id == "ATTNotice" {
                return Alert(title: Text("Tracking Request"),
                             message: Text("This free App is ads-Supported. We value our users' privary. Tracking will allow our ads providers to deliver personalized ads to you. Please make a choice in the next notice."),
                             dismissButton: .default(Text("Continue"), action: {
                    requestIDFA()
                }))
            }
            return Alert(
                title: Text(item.id),
                message: Text(item.msg ?? ""),
                primaryButton: .default(Text("OK"), action: item.action),
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $viewModel.initialTermsAgreementPresenting, onDismiss: {
            UserDefaults.standard.setValue(true, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
            viewModel.alertItem = AlertItem(id: "ATTNotice")
        }, content: {
            VStack(spacing: 4) {
                VStack(spacing: 16) {
                    Text("D.S.Reader").font(.title)

                    Image("logo_1024")
                        .resizable().frame(width: 128, height: 128, alignment: .center)

                    Text("")
                }
                Text("""
                    Welcome to D.S.Reader, an e-Book Reader for EPUB, PDF and CBZ formats, with custom fonts and custom dictionary support.

                    When paired with calibre Content Server, you can easily browse your libraries, download books for reading.
                    It will track and sync your reading progress and highlights across all devices paired with the same server.

                    Accept our "Private Policy" and "Terms & Conditions" to start.

                    (Dismissing this notice means you will accept.")
                    """)

                if let yabrPrivacyHtml = YabrAppInfo.shared.privacyHtml {
                    Button(action: { viewModel.privacyWebViewPresenting = true }) {
                        Text("Private Policy")
                    }.sheet(isPresented: $viewModel.privacyWebViewPresenting) {
                        WebViewUI(content: yabrPrivacyHtml, baseURL: YabrAppInfo.shared.baseUrl)
                    }
                }
                if let yabrTermsHtml = YabrAppInfo.shared.termsHtml {
                    Button(action: { viewModel.termsWebViewPresenting = true }) {
                        Text("Terms & Conditions")
                    }.sheet(isPresented: $viewModel.termsWebViewPresenting) {
                        WebViewUI(content: yabrTermsHtml, baseURL: YabrAppInfo.shared.baseUrl)
                    }
                }

                HStack {
                    Button(action: {
                        viewModel.declineTerms()
                    }) {
                        Text("Decline and Exit").foregroundColor(.red)
                    }.padding()

                    Button(action: {
                        viewModel.acceptTerms()
                    }) {
                        Text("Accept")
                    }.padding()
                }
            }.padding()
        })
        .actionSheet(isPresented: $viewModel.bookImportActionSheetPresenting, content: {
            guard let bookImportInfo = viewModel.bookImportInfo else {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Unexpected error occured (code empty result). Please consider report this."),
                    buttons: [
                        .default(Text("Report"), action: {
                            viewModel.reportImportError()
                        }),
                        .cancel()])
            }
            if bookImportInfo.error == nil, let bookId = bookImportInfo.bookId {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Imported, read now?"),
                    buttons: [
                        .default(Text("Read"), action: {
                            viewModel.openImportedBook()
                        }),
                        .cancel()
                    ]
                )
            }
            if bookImportInfo.error == .destConflict {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Book of same file name already exists. Do you wish to overwrite existing one?"),
                    buttons: [
                        .default(Text("As a new book"), action: {
                            viewModel.importBookAsNew(url: bookImportInfo.url, bookId: bookImportInfo.bookId)
                        }),
                        .destructive(Text("Overwrite"), action: {
                            viewModel.importBookOverwrite(url: bookImportInfo.url, bookId: bookImportInfo.bookId)
                        }),
                        .cancel()
                    ]
                )
            }
            return ActionSheet(
                title: Text("Importing"),
                message: Text("Unexpected error occured (code \(bookImportInfo.error?.rawValue ?? "unknown")). Please consider report this."),
                buttons: [
                    .default(Text("Report"), action: {
                        viewModel.reportImportError()
                    }),
                    .cancel()])
        })
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .font(.headline)
        .onOpenURL { url in
            print("onOpenURL \(url)")
            let result = container.bookManager.onOpenURL(url: url, doMove: false, doOverwrite: false, asNew: false)
            container.publishBookImport(result)
        }.onAppear {
            viewModel.onAppear()
        }
        .onChange(of: viewModel.consentRequestTriggered) { triggered in
            if triggered {
                requestIDFA()
                viewModel.consentRequestTriggered = false
            }
        }
        .onChange(of: viewModel.urlToOpen) { url in
            if let url = url {
                openURL(url)
                viewModel.urlToOpen = nil
            }
        }
        .environment(\.readerWorkspaceID, viewModel.readerWorkspaceViewModel.id)
    }

    private func requestIDFA() {
        ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in
            // Tracking authorization completed. Start loading ads here.
            showConsentInformation()
        })
    }

    private func showConsentInformation() {
        #if canImport(GoogleMobileAds)
        let parameters = RequestParameters()
        // false means users are not under age.
        parameters.isTaggedForUnderAgeOfConsent = false

        ConsentInformation.shared.requestConsentInfoUpdate(
            with: parameters,
            completionHandler: { error in
                if error != nil {
                    // Handle the error.
                } else {
                    // The consent information state was updated.
                    // You are now ready to check if a form is available.
                    let formStatus = ConsentInformation.shared.formStatus
                    if formStatus == FormStatus.available {
                        loadForm()
                    }
                }
            })
        #endif
    }

    #if canImport(GoogleMobileAds)
    private func loadForm() {
        ConsentForm.load(
            with: { form, loadError in
                guard loadError == nil else { return }
                guard ConsentInformation.shared.consentStatus == ConsentStatus.required else { return }
                guard let form = form,
                      let viewController = self.consentPresentationViewController else {
                    return
                }

                form.present(from: viewController, completionHandler: { dismissError in
                    self.startAdsIfConsentObtained()
                })
            })
    }

    private var consentPresentationViewController: UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        return windows.first { $0.isKeyWindow }?.rootViewController
            ?? windows.first?.rootViewController
    }

    private func startAdsIfConsentObtained() {
        guard ConsentInformation.shared.consentStatus == ConsentStatus.obtained else { return }

        // App can start requesting ads.
        MobileAds.shared.start(completionHandler: nil)
    }
    #endif
}

@available(macCatalyst 14.0, *)
private struct WelcomeEmptyShelfView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    let openSettings: () -> Void
    let openBrowse: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 22) {
                header
                summary
                actionButtons
                dismissHint
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .frame(maxWidth: 520)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 24)

            Spacer()
            Spacer(minLength: 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.08).ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("logo_1024")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 6) {
                Text("Welcome to D.S.Reader")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Your reading shelf is ready to be set up.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var summary: some View {
        Text("Connect a calibre library or browse available libraries to start building your reading shelf.")
            .font(.body)
            .foregroundColor(.primary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 10) {
                primaryAction
                secondaryAction
            }
        } else {
            HStack(spacing: 12) {
                primaryAction
                secondaryAction
            }
        }
    }

    private var primaryAction: some View {
        Button(action: openSettings) {
            Label("Set Up Server & Library", systemImage: "server.rack")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WelcomePrimaryButtonStyle())
        .accessibilityHint("Opens Settings to configure a calibre server and library.")
    }

    private var secondaryAction: some View {
        Button(action: openBrowse) {
            Label("Browse Libraries", systemImage: "building.columns")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WelcomeSecondaryButtonStyle())
        .accessibilityHint("Opens Browse to explore configured libraries.")
    }

    private var dismissHint: some View {
        Text("This panel disappears after your first book is added to the shelf.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WelcomePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundColor(.white)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.75) : Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WelcomeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundColor(.accentColor)
            .background(configuration.isPressed ? Color.accentColor.opacity(0.16) : Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
            )
    }
}

@available(macCatalyst 14.0, *)
private struct ReaderWorkspaceView: View {
    @ObservedObject var viewModel: ReaderWorkspaceViewModel
    @State private var toolbarHeight: CGFloat = 0

    private var toolbarPlacement: ReaderWorkspaceToolbarPlacement {
        #if targetEnvironment(macCatalyst)
        return .top
        #else
        return UIDevice.current.userInterfaceIdiom == .phone ? .bottom : .top
        #endif
    }

    private var readerToolbarInset: CGFloat {
        toolbarHeight > 0 ? toolbarHeight + 8 : 76
    }

    var body: some View {
        ZStack(alignment: toolbarPlacement.alignment) {
            Color.black.ignoresSafeArea()

            readerContent
                .padding(.top, toolbarPlacement == .top ? readerToolbarInset : 0)
                .padding(.bottom, toolbarPlacement == .bottom ? readerToolbarInset : 0)
                .ignoresSafeArea(.container, edges: toolbarPlacement.ignoredReaderEdges)

            readerToolbar
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ReaderToolbarHeightPreferenceKey.self, value: proxy.size.height)
                    }
                )
        }
        .onPreferenceChange(ReaderToolbarHeightPreferenceKey.self) { height in
            toolbarHeight = height
        }
        .opacity(viewModel.isPresented ? 1 : 0)
        .allowsHitTesting(viewModel.isPresented)
        .accessibilityHidden(viewModel.isPresented == false)
    }

    @ViewBuilder
    private var readerContent: some View {
        if viewModel.mountedPresentations.isEmpty == false {
            ZStack {
                ForEach(viewModel.mountedPresentations) { presentation in
                    let isActive = viewModel.activePresentationID == presentation.id
                    YabrEBookReaderRepresentable(
                        book: presentation.book,
                        readerInfo: presentation.readerInfo,
                        presentationID: presentation.id,
                        lifecycleEvents: {
                            viewModel.readerLifecycleEvents(for: presentation.id)
                        }
                    )
                    .id(presentation.id)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(isActive == false)
                    .zIndex(isActive ? 1 : 0)
                }
            }
        } else if viewModel.isPresented {
            NavigationView {
                Text("No Suitable Format/Reader/Position Combo")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: {
                                viewModel.hideReader()
                            }) {
                                Image(systemName: "xmark")
                            }
                        }
                    }
            }
        }
    }

    private var readerToolbar: some View {
        HStack(spacing: 8) {
            Button(action: {
                viewModel.hideReader()
            }) {
                Image(systemName: "rectangle.leadinghalf.inset.filled")
                    .frame(width: 28, height: 28)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.presentations) { presentation in
                        HStack(spacing: 6) {
                            Button(action: {
                                viewModel.activatePresentation(id: presentation.id)
                            }) {
                                Text(presentation.title)
                                    .lineLimit(1)
                                    .font(.caption)
                            }

                            Button(action: {
                                viewModel.closePresentation(id: presentation.id)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(viewModel.activePresentationID == presentation.id ? Color.accentColor : Color.secondary.opacity(0.35))
                        )
                        .foregroundColor(.white)
                        .contextMenu {
                            Button(action: {
                                viewModel.closePresentation(id: presentation.id)
                            }) {
                                Label("Close", systemImage: "xmark")
                            }
                        }
                    }
                }
            }

            if viewModel.supportsReaderWindows {
                Button(action: {
                    viewModel.openEmptyReaderWindow()
                }) {
                    Image(systemName: "plus.rectangle")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("New Window")
                .help("Open a new empty window")

                Button(action: {
                    viewModel.moveActivePresentationToNewWindow()
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Move Reader to New Window")
                .help("Move the current reader to a new window")
            }

            Button(action: {
                viewModel.closeActivePresentation()
            }) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.top, toolbarPlacement == .top ? 10 : 0)
        .padding(.bottom, toolbarPlacement == .bottom ? 10 : 0)
        .padding(.horizontal, 12)
    }
}

private enum ReaderWorkspaceToolbarPlacement {
    case top
    case bottom

    var alignment: Alignment {
        switch self {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }

    var ignoredReaderEdges: Edge.Set {
        switch self {
        case .top:
            return [.horizontal, .bottom]
        case .bottom:
            return [.horizontal]
        }
    }
}

private struct ReaderToolbarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@available(macCatalyst 14.0, *)
struct MainView_Previews: PreviewProvider {
    static private var container = AppContainer()

    static var previews: some View {
        MainView(container: container, viewModel: MainViewModel(container: container, sessionManager: container.sessionManager))
            .environment(\.appContainer, container)
    }
}
