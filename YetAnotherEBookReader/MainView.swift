//
//  MainView.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/24.
//

import SwiftUI
import Combine
import AppTrackingTransparency

#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform
#endif

@available(macCatalyst 14.0, *)
struct MainView: View {
    @EnvironmentObject var modelData: ModelData
    @Environment(\.openURL) var openURL

    @State private var alertItem: AlertItem?

    @State private var initialTermsAgreementPresenting = false
    @State private var privacyWebViewPresenting = false
    @State private var termsWebViewPresenting = false
    
    @State private var positionActionPresenting = false
    @State private var positionActionMessage = ""
    
    @State private var bookImportedCancellable: AnyCancellable?
    @State private var dismissAllCancellable: AnyCancellable?

    @State private var bookImportActionSheetPresenting = false
    @State private var bookImportInfo: BookImportInfo?
    
    @State private var umpFormLoaded = false
    
    private let issueURL = "https://github.com/drearycold/YetAnotherEBookReader/issues/new?labels=bug&assignees=drearycold"

    var body: some View {
        ZStack {
            TabView(selection: $modelData.activeTab) {
                RecentShelfUI()
                    .tabItem {
                        Image(systemName: "doc.text.fill")
                        Text("Recent")
                    }
                    .tag(0)
                    
                SectionShelfUI()
                    .tabItem {
                        Image(systemName: "books.vertical.fill")
                        Text("Discover")
                    }
                    .tag(1)
                
                LibraryInfoView()
                    .tabItem {
                        Image(systemName: "building.columns.fill")
                        Text("Browse")
                    }
                    .tag(2)
                
                NavigationView {
                    SettingsView()
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(3)
            }
            if modelData.activeTab < 1 && modelData.booksInShelf.isEmpty {
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
        .fullScreenCover(isPresented: $modelData.presentingEBookReaderFromShelf, onDismiss: {
            guard let book = modelData.readingBook, let readerInfo = modelData.readerInfo else { return }

            modelData.logBookDeviceReadingPositionHistoryFinish(book: book, endPosition: modelData.updatedReadingPosition)

            let originalPosition = readerInfo.position
            if modelData.updatedReadingPosition.isSameProgress(with: originalPosition) {
                return
            }
            if false && modelData.updatedReadingPosition < originalPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    alertItem = AlertItem(
                        id: "BackwardProgress",
                        msg: "You have reached a position behind last saved, is this alright?"
                    )
                }
            } else if false && originalPosition << modelData.updatedReadingPosition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    alertItem = AlertItem(
                        id: "ForwardProgress",
                        msg: "You have advanced more than 10% in this book, is this alright?"
                    )
                }
            }
            else {
                modelData.updateCurrentPosition(alertDelegate: nil)
                NotificationCenter.default.post(Notification(name: .YABR_BooksRefreshed))
            }
        }) {
            if let book = modelData.readingBook, let readerInfo = modelData.readerInfo {
                YabrEBookReader(book: book, readerInfo: readerInfo)
            } else {
                Text("No Suitable Format/Reader/Position Combo")
            }
        }
        .alert(item: $alertItem) { item in
            if item.id == "ForwardProgress" || item.id == "BackwardProgress" {
                return Alert(
                    title: Text("Confirm New Progress"),
                    message: Text(item.msg ?? ""),
                    primaryButton: .destructive(Text("Confirm")) {
                        modelData.updateCurrentPosition(alertDelegate: self)
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
        .sheet(isPresented: $initialTermsAgreementPresenting, onDismiss: {
            UserDefaults.standard.setValue(true, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
            alertItem = AlertItem(id: "ATTNotice")
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
                Button(action: { privacyWebViewPresenting = true }) {
                    Text("Private Policy")
                }.sheet(isPresented: $privacyWebViewPresenting) {
                    SupportInfoView.privacyWebView()
                }
                Button(action: { termsWebViewPresenting = true }) {
                    Text("Terms & Conditions")
                }.sheet(isPresented: $termsWebViewPresenting) {
                    SupportInfoView.termsWebView()
                }
                
                HStack {
                    Button(action: {
                        UserDefaults.standard.setValue(false, forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
                        exit(1)
                    }) {
                        Text("Decline and Exit").foregroundColor(.red)
                    }.padding()
                    
                    Button(action: {
                        initialTermsAgreementPresenting = false
                    }) {
                        Text("Accept")
                    }.padding()
                }
            }.padding()
        })
        .actionSheet(isPresented: $bookImportActionSheetPresenting, content: {
            guard let bookImportInfo = bookImportInfo else {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Unexpected error occured (code empty result). Please consider report this."),
                    buttons: [
                        .default(Text("Report"), action: {
                            openURL(URL(string: issueURL + "&title=Error+Importing+Book+Empty+Result&body=")!)
                        }),
                        .cancel()])
            }
            if bookImportInfo.error == nil, let bookId = bookImportInfo.bookId {
                return ActionSheet(
                    title: Text("Importing"),
                    message: Text("Imported, read now?"),
                    buttons: [
                        .default(Text("Read"), action: {
                            guard let localLibrary = modelData.localLibrary else { return }
                            let book = CalibreBook(id: bookId, library: localLibrary)
                            modelData.readingBookInShelfId = book.inShelfId
                            guard modelData.readingBook != nil, modelData.readerInfo != nil else { return }

                            modelData.presentingEBookReaderFromShelf = true
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
                            let result = modelData.onOpenURL(url: bookImportInfo.url, doMove: false, doOverwrite: false, asNew: true, knownBookId: bookImportInfo.bookId)
                            NotificationCenter.default.post(name: .YABR_BookImported, object: nil, userInfo: ["result": result])
                        }),
                        .destructive(Text("Overwrite"), action: {
                            let result = modelData.onOpenURL(url: bookImportInfo.url, doMove: false, doOverwrite: true, asNew: false, knownBookId: bookImportInfo.bookId)
                            NotificationCenter.default.post(name: .YABR_BookImported, object: nil, userInfo: ["result": result])
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
                        openURL(URL(string: issueURL + "&title=Error+Importing+Book+\(String(describing: bookImportInfo.error))&body=")!)
                    }),
                    .cancel()])
        })
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .font(.headline)
        .onOpenURL { url in
            print("onOpenURL \(url)")
            let result = modelData.onOpenURL(url: url, doMove: false, doOverwrite: false, asNew: false)
            
            NotificationCenter.default.post(name: .YABR_BookImported, object: nil, userInfo: ["result": result])
        }.onAppear {
            let termsAccepted = UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_INITIAL_TERMS_ACCEPTED)
            if !termsAccepted {
                initialTermsAgreementPresenting = true
            } else {
                requestIDFA()
            }
            
            dismissAllCancellable?.cancel()
            dismissAllCancellable = modelData.dismissAllPublisher.sink { _ in
                modelData.presentingEBookReaderFromShelf = false
                positionActionPresenting = false
            }

            bookImportedCancellable?.cancel()
            bookImportedCancellable = modelData.bookImportedPublisher.sink { notification in
                print("bookImportedCancellable sink \(notification)")
                guard let info = notification.userInfo?["result"] as? BookImportInfo else { return }
                bookImportInfo = info
                
                print("dismissAll \(modelData.presentingStack.count)")
                dismissAll() {
                    NotificationCenter.default.post(name: .YABR_DismissAll, object: nil)
                    modelData.activeTab = 0

                    bookImportActionSheetPresenting = false
                    DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(250))) {
                        bookImportActionSheetPresenting = true
                    }
                }
            }
        }
        
    }
    
    private func dismissAll(completion: @escaping () -> Void) {
        print("dismissAll \(modelData.presentingStack)")
        
        if let latest = modelData.presentingStack.last {
            if latest.wrappedValue == true {
                latest.wrappedValue = false
                print("dismissAll dismissed \(latest)")
                DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(250))) {
                    dismissAll(completion: completion)
                }
            } else {
                print("dismissAll already dismissed \(latest)")
                _ = modelData.presentingStack.popLast()
                dismissAll(completion: completion)
            }
        } else {
            completion()
        }
    }
    
    private func requestIDFA() {
        ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in
            // Tracking authorization completed. Start loading ads here.
            showConsentInformation()
        })
    }

    private func showConsentInformation() {
        let parameters = UMPRequestParameters()
//        #if DEBUG
//        let debugSettings = UMPDebugSettings()
//        debugSettings.testDeviceIdentifiers = ["kGADSimulatorID"]
//        debugSettings.geography = UMPDebugGeography.EEA
//        parameters.debugSettings = debugSettings
//        #endif

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

extension MainView: AlertDelegate {
    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }
}

@available(macCatalyst 14.0, *)
struct MainView_Previews: PreviewProvider {
    static private var modelData = ModelData()
    
    static var previews: some View {
        MainView()
            .environmentObject(modelData)
        // ReaderView()
    }
}
