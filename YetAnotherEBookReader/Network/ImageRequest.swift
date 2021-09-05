//
//  ImageRequest.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/7/22.
//

import Foundation
import Kingfisher

class AuthPlugin: ImageDownloadRequestModifier {
    let modelData: ModelData
    
    init(modelData: ModelData) {
        self.modelData = modelData
    }
    
    func modified(for request: URLRequest) -> URLRequest? {
        var request = request
        guard let url = request.url, let query = url.query else { return request }
        print("AuthPlugin modified url \(url.absoluteString)")
        modelData.calibreServers.values.forEach { server in
            if url.absoluteString.starts(with: server.serverUrl) && server.serverUrl.hasPrefix("https://") && server.username.isEmpty == false && query.hasSuffix("&username=\(server.username)"){
                let toEncode = "\(server.username):\(server.password)";
                guard let encoded = toEncode.data(using: .utf8)?.base64EncodedString() else { return }
                request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
            }
        }
        return request
    }
}

class AuthResponsor: AuthenticationChallengeResponsable {
//    let modelData: ModelData
//
//    init(modelData: ModelData) {
//        self.modelData = modelData
//    }
//    
//    func downloader(
//        _ downloader: ImageDownloader,
//        didReceive challenge: URLAuthenticationChallenge,
//        completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
//    {
//        // Provide your `AuthChallengeDisposition` and `URLCredential`
//        var disposition: URLSession.AuthChallengeDisposition = .performDefaultHandling
//        var credential: URLCredential? = nil
//
//        completionHandler(disposition, credential)
//    }
    
    func downloader(
        _ downloader: ImageDownloader,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
    {
        guard let url = task.originalRequest?.url,
              let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = urlComponents.queryItems,
              let usernameItem = queryItems.filter({ $0.name == "username" && ($0.value?.count ?? 0) > 0 }).first
              else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                      port: url.port!,
                                                      protocol: url.scheme,
                                                      realm: "calibre",
                                                      authenticationMethod: NSURLAuthenticationMethodHTTPDigest)
        guard let credentials = URLCredentialStorage.shared.credentials(for: protectionSpace),
              let credential = credentials.filter({ $0.key == usernameItem.value }).first?.value
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        completionHandler(.useCredential, credential)
    }
}
