//
//  SectionShelfController.swift
//  ShelfView_Example
//
//  Created by Adeyinka Adediji on 26/12/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import ShelfView
import SwiftUI
import Combine
import RealmSwift

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

class SectionShelfController: UIViewController, SectionShelfCompositionalViewDelegate {
    var tabBarHeight = CGFloat(0)
    
    var shelfView: SectionShelfCompositionalView!

    let activityIndicatorView = UIActivityIndicatorView()
    
    #if canImport(GoogleMobileAds)
    var bannerSize = GADAdSizeBanner
    var bannerView: GADBannerView!
    var gadRequestInitialized = false
    #else
    var bannerSize = CGRect.zero
    #endif

    var modelData: ModelData!
    var generatingCancellable: AnyCancellable?
    var reloadShelfCancellable: AnyCancellable?
    
    let topButton = UIButton(type: .system)
    let topMenu = UIMenu(title: "Pick Library")
    var librariesPicked = Set<String>()     //set of libraryId

    let snaptshotQueue = DispatchQueue(label: "section-shelf-snapshot", qos: .userInitiated)
    
    let refreshBarButtonItem = BarButtonItem()
    
    ///
    var shelfObjects: [SearchCriteriaMergedKey: CalibreUnifiedSearchObject] = [:]
    var cancellables: Set<AnyCancellable> = []
    
    override var canBecomeFirstResponder: Bool {
        true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        resizeSubviews(to: view.frame.size, to: traitCollection)
        
        #if canImport(GoogleMobileAds)
        #if GAD_ENABLED
        guard gadRequestInitialized == false else { return }
        gadRequestInitialized = true
        let gadRequest = GADRequest()
        gadRequest.scene = self.view.window?.windowScene
        bannerView.load(gadRequest)
        #endif
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let tabBarController = self.tabBarController {
            tabBarHeight = tabBarController.tabBar.frame.height
        }
        
        #if canImport(GoogleMobileAds)
        shelfView = SectionShelfCompositionalView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: view.frame.width,
                height: view.frame.height - GADAdSizeBanner.size.height
            )
        )
        shelfView.translatesAutoresizingMaskIntoConstraints = false
        
        print("SECTIONFRAME \(view.frame) \(GADAdSizeBanner.size) \(tabBarHeight)")
        
        shelfView.delegate = self
        view.addSubview(shelfView)
        
        bannerView = GADBannerView(
            frame: CGRect(
                x: 0,
                y: shelfView.frame.maxY,
                width:  GADAdSizeBanner.size.width,
                height: GADAdSizeBanner.size.height))
        bannerView.adUnitID = modelData.yabrGADBannerShelfUnitID

        #if DEBUG
        if let yabrGADDeviceIdentifierTest = modelData.yabrGADDeviceIdentifierTest {
            GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [ yabrGADDeviceIdentifierTest ]
        }
        #endif
        bannerView.rootViewController = self
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.adSize = GADAdSizeBanner
        
        view.addSubview(bannerView)
        
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: bannerView.topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            bannerView.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: kGADAdSizeBanner.size.height / -2)
        ])
        
        #else
        shelfView = SectionShelfCompositionalView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: view.frame.width,
                height: view.frame.height
            )
        )
        shelfView.translatesAutoresizingMaskIntoConstraints = false
        
        shelfView.delegate = self
        view.addSubview(shelfView)
        NSLayoutConstraint.activate([
            shelfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelfView.topAnchor.constraint(equalTo: view.topAnchor),
            shelfView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        #endif
        
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.style = self.traitCollection.horizontalSizeClass == .regular ? .large : .medium
        view.addSubview(activityIndicatorView)
        
        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: shelfView.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: shelfView.centerYAnchor),
            activityIndicatorView.widthAnchor.constraint(equalTo: shelfView.widthAnchor, multiplier: self.traitCollection.horizontalSizeClass == .regular ? 0.25 : 0.5),
            activityIndicatorView.heightAnchor.constraint(equalTo: activityIndicatorView.widthAnchor)
        ])
        
        reloadShelfCancellable?.cancel()
        reloadShelfCancellable = modelData.discoverShelfModelSubject
            .collect(.byTime(RunLoop.main, .seconds(2)))
            .receive(on: snaptshotQueue)
            .map { shelfModelsArray -> ([ShelfModelSection], [UIMenuElement]) in
                guard let shelfModels = shelfModelsArray.last
                else {
                    return ([], [])
                }
                let librarySet = Set<CalibreLibrary>(shelfModels.compactMap { shelfModel -> CalibreLibrary? in
                    guard let libraryId = ModelData.parseShelfSectionId(sectionId: shelfModel.sectionId)
                    else { return nil }
                    
                    return self.modelData.calibreLibraries[libraryId]
                })
                
                let topMenuElements = [
                    UIAction(title: "    Reset") { action in
                        self.librariesPicked.removeAll(keepingCapacity: true)
                        self.modelData.discoverShelfModelSubject.send(self.modelData.bookModelSection)
                    }
                ] + librarySet.sorted(by: {
                    $0.name < $1.name
                })
                .map { library -> UIAction in
                    UIAction(title: (self.librariesPicked.contains(library.id) ? " ✓ " : "    " ) + library.name + " on " + library.server.name) { action in
                        self.librariesPicked.formSymmetricDifference([library.id])
                        self.modelData.discoverShelfModelSubject.send(self.modelData.bookModelSection)
                    }
                }
                
                return (shelfModels, topMenuElements)
            }
            .receive(on: DispatchQueue.main)
            .map { shelfModels, topMenuElements -> [ShelfModelSection] in
                self.topButton.menu = self.topMenu.replacingChildren(topMenuElements)
                
                self.librariesPicked.formIntersection(
                    shelfModels.compactMap {
                        ModelData.parseShelfSectionId(sectionId: $0.sectionId)
                    }
                )
                
                let shelfModelsSelected = shelfModels.filter {
                    guard let libraryId = ModelData.parseShelfSectionId(sectionId: $0.sectionId)
                    else { return false }
                    
                    return self.librariesPicked.isEmpty || self.librariesPicked.contains(libraryId)
                }
                
                return shelfModelsSelected
            }
            .receive(on: snaptshotQueue)
            .sink { shelfModels in
                var snapshot = shelfModels.reduce(
                    into: NSDiffableDataSourceSnapshot<ShelfModelSection, ShelfModel>(),
                    { partialResult, section in
                        var sectionShelf = section.sectionShelf
                        
                        sectionShelf[sectionShelf.startIndex].type = .left
                        sectionShelf[sectionShelf.endIndex-1].type = .right
                        
                        partialResult.appendSections([ShelfModelSection(sectionName: section.sectionName, sectionId: section.sectionId, sectionShelf: [])])
                        
                        partialResult.appendItems(sectionShelf)
                    })
                
                self.fillSnapshotToScreen(snapshot: &snapshot)
                
//                self.shelfView.applyDataSourceSnapshot(snapshot: snapshot)
            }
        
        let navBarBackgroundImage = Utils().loadImage(name: "header")?.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5))
        
        let navBarScrollApp = UINavigationBarAppearance()
        navBarScrollApp.configureWithTransparentBackground()
        navBarScrollApp.backgroundImage = navBarBackgroundImage
        self.navigationController?.navigationBar.standardAppearance = navBarScrollApp
        self.navigationController?.navigationBar.scrollEdgeAppearance = navBarScrollApp
        
        topButton.setTitle("Libraries", for: .normal)
        topButton.menu = topMenu
        topButton.showsMenuAsPrimaryAction = true
        self.navigationItem.titleView = topButton
        
        refreshBarButtonItem.primaryAction = .init(title: "Refresh", handler: { action in
//            self.modelData.calibreUpdatedSubject.send(.shelf)
            self.modelData.shelfDataModel.refresh()
        })
        
        self.navigationItem.setLeftBarButtonItems([
            refreshBarButtonItem
        ], animated: false)
        
        self.navigationItem.setRightBarButtonItems([
            self.editButtonItem
        ], animated: false)
        
        let toolBarApp = UIToolbarAppearance()
        toolBarApp.configureWithOpaqueBackground()
        toolBarApp.backgroundImage = navBarBackgroundImage
        self.navigationController?.toolbar.standardAppearance = toolBarApp
        self.navigationController?.toolbar.scrollEdgeAppearance = toolBarApp
        
        self.setToolbarItems([
            .init(title: "Select All", style: .plain, target: shelfView, action: #selector(shelfView.selectAll(_:))),
            UIBarButtonItem.flexibleSpace(),
            .init(title: "Download", style: .done, target: self, action: #selector(download(_:))),
            UIBarButtonItem.flexibleSpace(),
            .init(title: "Clear", style: .plain, target: shelfView, action: #selector(shelfView.clearSelection(_:)))
        ], animated: true)
        
        
        ///
        /*
        modelData.librarySearchManager.cacheRealmQueue.sync {
            let lastAdded = SearchCriteriaMergedKey(libraryIds: [], criteria: .init(searchString: "", sortCriteria: .init(by: .Added, ascending: false), filterCriteriaCategory: [:]))
            
            let lastAddedObject = modelData.librarySearchManager.getUnifiedResult(libraryIds: lastAdded.libraryIds, searchCriteria: lastAdded.criteria)
            
            shelfObjects[lastAdded] = lastAddedObject
            
            shelfObjects = modelData.booksInShelf.reduce(into: shelfObjects) { partialResult, bookEntry in
                
            }
            
            valuePublisher(lastAddedObject, keyPaths: ["books"])
                .receive(on: modelData.librarySearchManager.cacheRealmQueue)
                .map { object -> ShelfModelSection in
                    print("\(#function) lastAddedObject changed books.count=\(object.books.count)")
                    
                    let shelfModels: [ShelfModel] = object.books.prefix(20).map { book -> ShelfModel in
                            .init(bookCoverSource: "", bookId: book.primaryKey!, bookTitle: book.title, bookProgress: 0, bookStatus: .READY, sectionId: "last-added")
                    }
                    
                    return .init(sectionName: "Last Added", sectionId: "last-added", sectionShelf: shelfModels)
                }
                .receive(on: snaptshotQueue)
                .sink { completion in
                    
                } receiveValue: { section in
                    let shelfModels = [section]
                    var snapshot = shelfModels.reduce(
                        into: NSDiffableDataSourceSnapshot<ShelfModelSection, ShelfModel>(),
                        { partialResult, section in
                            var sectionShelf = section.sectionShelf
                            
                            sectionShelf[sectionShelf.startIndex].type = .left
                            sectionShelf[sectionShelf.endIndex-1].type = .right
                            
                            partialResult.appendSections([ShelfModelSection(sectionName: section.sectionName, sectionId: section.sectionId, sectionShelf: [])])
                            
                            partialResult.appendItems(sectionShelf)
                        })
                    
                    self.fillSnapshotToScreen(snapshot: &snapshot)
                    
                    self.shelfView.applyDataSourceSnapshot(snapshot: snapshot)
                }
                .store(in: &cancellables)
        }
        */
        
        
        /*
        modelData.shelfDataModel.$discoverShelf
            .receive(on: snaptshotQueue)
            .sink { discoverShelf in
                print("\(#function) discoverShelf \(discoverShelf.count)")
                
                var snapshot = self.buildSnapshot(shelf: discoverShelf)
                
                self.fillSnapshotToScreen(snapshot: &snapshot)
                self.shelfView.applyDataSourceSnapshot(snapshot: snapshot)
            }
            .store(in: &cancellables)
        */
        
        modelData.shelfDataModel.discoverShelfSubject
            .receive(on: snaptshotQueue)
            .sink { discoverShelf in
                print("\(#function) discoverShelf \(discoverShelf.count)")
                
                var snapshot = self.buildSnapshot(shelf: discoverShelf)
                
                self.fillSnapshotToScreen(snapshot: &snapshot)
                self.shelfView.applyDataSourceSnapshot(snapshot: snapshot)
            }
            .store(in: &cancellables)
        
        self.snaptshotQueue.async {
            var snapshot = self.buildSnapshot(shelf: self.modelData.shelfDataModel.discoverShelf)
            
            self.fillSnapshotToScreen(snapshot: &snapshot)
            self.shelfView.applyDataSourceSnapshot(snapshot: snapshot)
        }
    }
    
    func buildSnapshot(shelf: [String: ShelfModelSection]) -> NSDiffableDataSourceSnapshot<ShelfModelSection, ShelfModel> {
        shelf.sorted(by: { $0.value.sectionName < $1.value.sectionName }).reduce(
            into: .init(),
            { partialResult, sectionEntry in
                let section = sectionEntry.value
                
                var sectionShelf = section.sectionShelf
                
                sectionShelf[sectionShelf.startIndex].type = .left
                sectionShelf[sectionShelf.endIndex-1].type = .right
                
                partialResult.appendSections([ShelfModelSection(sectionName: section.sectionName, sectionId: section.sectionId, sectionShelf: [])])
                
                partialResult.appendItems(sectionShelf)
            })
    }
    
    func fillSnapshotToScreen(snapshot: inout NSDiffableDataSourceSnapshot<ShelfModelSection, ShelfModel>) {
        while snapshot.numberOfSections < Int(self.shelfView.grids.height) {
            let sectionId = LibrarySearchKey(
                libraryId: self.modelData.localLibrary?.id ?? "",
                criteria: .init(
                    searchString: "\(snapshot.numberOfSections)",
                    sortCriteria: .init(),
                    filterCriteriaCategory: [:]
                )
            ).description
            
            snapshot.appendSections([.init(
                sectionName: "",
                sectionId: sectionId,
                sectionShelf: [])])
            
            snapshot.appendItems(
                (0 ..< Int(self.shelfView.grids.width)).map {
                    ShelfModel(
                        bookId: "row-\(snapshot.numberOfSections)-\($0)",
                        sectionId: sectionId,
                        show: false,
                        type: .center
                    )
                }
            )
        }
    }
    
    func resizeSubviews(to size: CGSize, to newCollection: UITraitCollection) {
        if let tabBarController = self.tabBarController {
            tabBarHeight = tabBarController.tabBar.frame.height
        }
        
        #if canImport(GoogleMobileAds)
        if newCollection.horizontalSizeClass == .regular && newCollection.verticalSizeClass == .regular {
            bannerSize = GADAdSizeLeaderboard
        }
        if newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .regular {
            bannerSize = GADAdSizeLargeBanner
        }
        if newCollection.horizontalSizeClass == .regular && newCollection.verticalSizeClass == .compact {
            bannerSize = GADAdSizeFullBanner
        }
        if newCollection.horizontalSizeClass == .compact && newCollection.verticalSizeClass == .compact {
            bannerSize = GADAdSizeBanner
        }
        
        bannerView.adSize = bannerSize
        
        bannerView.frame = CGRect(
            x: (size.width - bannerSize.size.width) / 2,
            y: size.height - bannerSize.size.height,
            width: bannerSize.size.width,
            height: bannerSize.size.height
        )
        
        #endif
        
        shelfView.frame = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: size.height - bannerSize.size.height
        )
        
        #if canImport(GoogleMobileAds)
        print("SECTIONFRAME \(view.frame) \(shelfView.frame) \(bannerView.frame) \(tabBarHeight) \(bannerSize.size)")
        #endif
        
        shelfView.resize(to: size)
    }
    
//    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
//        coordinator.animate { _ in
//            self.resizeSubviews(to: self.view.frame.size, to: newCollection)
//        } completion: { _ in
//
//        }
//
//    }
//    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate { _ in
            self.resizeSubviews(to: size, to: self.traitCollection)
        } completion: { _ in
        }
        
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        shelfView.setEditing(editing)
        
        self.navigationController?.setToolbarHidden(!editing, animated: false)
        
        if self.navigationController?.isToolbarHidden == false,
           let toolbar = self.navigationController?.toolbar {
            NSLayoutConstraint.activate([
                toolbar.bottomAnchor.constraint(equalTo: shelfView.bottomAnchor)
            ])
        }
        
//        if editing == false {
            self.resizeSubviews(to: self.view.frame.size, to: self.traitCollection)
//        }
    }
    
    func onBookClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String) {
//        print("I just clicked \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")
//
//        modelData.readingBookInShelfId = bookId
//
//        guard modelData.readingBook != nil else {
//            let alert = UIAlertController(title: "Missing Book File", message: "Re-download from Server?", preferredStyle: .alert)
//            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
//                alert.dismiss(animated: true, completion: nil)
//            })
//            alert.addAction(UIAlertAction(title: "Download", style: .default) { _ in
//                alert.dismiss(animated: true, completion: nil)
//            })
//            self.present(alert, animated: true, completion: nil)
//            return
//        }
//        modelData.presentingEBookReaderFromShelf = true
//
//        guard let book = modelData.readingBook, let readerInfo = modelData.readerInfo else { return }
//        modelData.logBookDeviceReadingPositionHistoryStart(book: book, startPosition: readerInfo.position, startDatetime: Date())
        
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")

        modelData.readingBookInShelfId = bookId
//        let detailMenuItem = UIMenuItem(title: "Details", action: #selector(onBookLongClickedDetailMenuItem(_:)))
//        UIMenuController.shared.menuItems = [detailMenuItem]
//        becomeFirstResponder()
//        UIMenuController.shared.showMenu(from: shelfView, rect: inShelfView)
        
        guard let bookRealm = modelData.getBookRealm(forPrimaryKey: bookId)
        else {
            return
        }
        
        let bookDetailView = BookDetailView(book: bookRealm, viewMode: .SHELF).environmentObject(modelData)
        let detailView = UIHostingController(
            rootView: bookDetailView
        )
        
        let nav = UINavigationController(rootViewController: detailView)
        nav.modalPresentationStyle = .fullScreen
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.prefersLargeTitles = true
        //nav.setToolbarHidden(false, animated: true)
        
        detailView.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        self.present(nav, animated: true, completion: nil)
    }

    func onBookLongClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked longer \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")

        modelData.readingBookInShelfId = bookId
//        let detailMenuItem = UIMenuItem(title: "Details", action: #selector(onBookLongClickedDetailMenuItem(_:)))
//        UIMenuController.shared.menuItems = [detailMenuItem]
//        becomeFirstResponder()
//        UIMenuController.shared.showMenu(from: shelfView, rect: inShelfView)
        
        guard let bookRealm = modelData.getBookRealm(forPrimaryKey: bookId)
        else {
            return
        }
        
        let bookDetailView = BookDetailView(book: bookRealm, viewMode: .SHELF).environmentObject(modelData)
        let detailView = UIHostingController(
            rootView: bookDetailView
        )
        
        let nav = UINavigationController(rootViewController: detailView)
        nav.modalPresentationStyle = .fullScreen
        nav.navigationBar.isTranslucent = true
        nav.navigationBar.prefersLargeTitles = true
        //nav.setToolbarHidden(false, animated: true)
        
        detailView.navigationItem.setLeftBarButton(UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(finishReading(sender:))), animated: true)
        
        self.present(nav, animated: true, completion: nil)
    }
    
    func onBookOptionsClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        
    }
    
    func onBookRefreshClicked(_ shelfView: SectionShelfCompositionalView, section: Int, index: Int, sectionId: String, sectionTitle: String, bookId: String, bookTitle: String, frame inShelfView: CGRect) {
        print("I just clicked refresh \"\(bookTitle)\" with bookId \(bookId), at index \(index). Section details --> section \(section), sectionId \(sectionId), sectionTitle \(sectionTitle)")
        
        guard let book = modelData.booksInShelf[bookId] else { return }
        
        book.formats.filter {
            $1.cached && !$1.cacheUptoDate
        }.keys.forEach {
            guard let format = Format(rawValue: $0) else { return }

            self.modelData.bookFormatDownloadSubject.send((book: book, format: format))
        }
    }
    
    @objc func finishReading(sender: UIBarButtonItem) {
        self.dismiss(animated: true) {
            self.modelData.readingBookInShelfId = nil
        }
    }
    
    @objc func download(_ sender: Any?) {
        let count = self.shelfView.selectedBookIds.count
        guard count > 0 else { return }
        
        let alert = UIAlertController(title: "Download Books?", message: "Will add \(count) books to reading shelf, are you sure?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        alert.addAction(UIAlertAction(title: "Download", style: .default) { _ in
//            self.suspendNotificationHandler()
            
            self.shelfView.selectedBookIds.forEach { bookId in
                guard let book = self.modelData.getBook(for: bookId),
                      let format = self.modelData.getPreferredFormat(for: book)
                else { return }
                
                self.modelData.addToShelf(book: book, formats: [format])
            }
            
            self.setEditing(false, animated: true)
            
//            self.registerNotificationHandler()
            
//            self.modelData.calibreUpdatedSubject.send(.shelf)
        })
        
        self.present(alert, animated: true)
    }
}
