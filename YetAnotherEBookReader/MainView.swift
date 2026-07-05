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
                VStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Welcome!")

                        Text("""
                        Get start from
                        \"Settings\" -> \"Server & Library\"
                        to link with Calibre Server.
                        """)

                        Text("""
                        Then go to "Browse"
                        to add book to Shelf by toggling \(Image(systemName: "star"))
                        or by downloading (\(Image(systemName: "tray.and.arrow.down"))) individual format.
                        """)

                        Text("Start reading by touching book cover.")

                        Text("Don't forget to play with \"Reader Options\" and various in-reader settings.")

                        Text("Enjoy your book!")

                        Text("(This notice will disappear after first book has been added to shelf)")
                    }
                    .multilineTextAlignment(.leading)
                    .padding()
                    .background(Color.gray.opacity(0.5).cornerRadius(16).frame(minWidth: 300, minHeight: 360))
                    .frame(maxWidth: 400)

                    Rectangle().frame(height: 50).opacity(0.0)
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.presentingEBookReaderFromShelf) {
            if let book = viewModel.readingBook, let readerInfo = viewModel.readerInfo {
                YabrEBookReader(book: book, readerInfo: readerInfo)
            } else {
                NavigationView {
                    Text("No Suitable Format/Reader/Position Combo")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(action: {
                                    viewModel.presentingEBookReaderFromShelf = false
                                }) {
                                    Image(systemName: "xmark")
                                }
                            }
                        }
                }
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
    }

    private func requestIDFA() {
        ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in
            // Tracking authorization completed. Start loading ads here.
            showConsentInformation()
        })
    }

    private func showConsentInformation() {
        #if canImport(GoogleMobileAds)
        let parameters = UMPRequestParameters()
        // false means users are not under age.
        parameters.tagForUnderAgeOfConsent = false

        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(
            with: parameters,
            completionHandler: { error in
                if error != nil {
                    // Handle the error.
                } else {
                    // The consent information state was updated.
                    // You are now ready to check if a form is available.
                    let formStatus = UMPConsentInformation.sharedInstance.formStatus
                    if formStatus == UMPFormStatus.available {
                        loadForm()
                    }
                }
            })
        #endif
    }

    #if canImport(GoogleMobileAds)
    private func loadForm() {
        UMPConsentForm.load(
            completionHandler: { form, loadError in
                if loadError != nil {
                    // Handle the error
                } else {
                    // Present the form
                    if UMPConsentInformation.sharedInstance.consentStatus == UMPConsentStatus.required {
                        form?.present(from: UIApplication.shared.windows.first!.rootViewController! as UIViewController, completionHandler: { dimissError in
                            if UMPConsentInformation.sharedInstance.consentStatus == UMPConsentStatus.obtained {
                                // App can start requesting ads.
                                GADMobileAds.sharedInstance().start(completionHandler: nil)
                            }
                        })
                    }
                }
            })
    }
    #endif
}

@available(macCatalyst 14.0, *)
struct MainView_Previews: PreviewProvider {
    static private var container = AppContainer()

    static var previews: some View {
        MainView(container: container, viewModel: MainViewModel(container: container, sessionManager: container.sessionManager))
            .environment(\.appContainer, container)
    }
}
