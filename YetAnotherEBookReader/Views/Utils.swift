//
//  Utils.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/4.
//

import SwiftUI
import Combine
import Foundation

class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    let url: URL
    private var cancellable: AnyCancellable?

    init(url: URL) {
        self.url = url
    }

    deinit {
        cancel()
    }
    
    func load() {
        cancellable = URLSession.shared.dataTaskPublisher(for: url)
                    .map { UIImage(data: $0.data) }
                    .replaceError(with: nil)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] in self?.image = $0 }
    }

    func cancel() {
        cancellable?.cancel()
    }
}

struct AsyncImage<Placeholder: View>: View {
    @EnvironmentObject var modelData: ModelData

    @StateObject private var loader: ImageLoader
    private let placeholder: Placeholder

    init(url: URL, @ViewBuilder placeholder: () -> Placeholder) {
        print("AsyncImage URL \(url.absoluteString)")
        self.placeholder = placeholder()
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
    }

    var body: some View {
        content
            .onAppear {
                print("AsyncImage onAppear \(loader.url.absoluteString)")
                loader.load()
            }
            .onReceive(modelData.readingBookReloadCover) { (_) in
                print("AsyncImage onReceive \(loader.url.absoluteString)")
                loader.load()
            }
    }

    private var content: some View {
        Group {
            if loader.image != nil {
                Image(uiImage: loader.image!)
                    .resizable().frame(width: 300.0, height: 400.0, alignment: .center)
            } else {
                placeholder
            }
        }
    }
}

struct TestView: View {
    let url = URL(string: "https://image.tmdb.org/t/p/original/pThyQovXQrw2m0s9x82twj48Jq4.jpg")!
    
    var body: some View {
        AsyncImage(
            url: url) {
            Text("Loading ...")
        }.aspectRatio(contentMode: .fit)
    }
}
