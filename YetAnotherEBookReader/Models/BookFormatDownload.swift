//
//  DownloadDelegate.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/9.
//

import Foundation
import OSLog

struct BookFormatDownloadService {
    var defaultLog = Logger()
    var modelData: ModelData

    func cancelDownload(_ book: CalibreBook, format: Format) {
        guard let download = modelData.activeDownloads.filter({
                    $1.book.id == book.id && $1.format == format
            && ($1.isDownloading || $1.resumeData != nil)
        }).first else {
            return
        }
        
        download.value.downloadTask?.cancel()
        
        modelData.activeDownloads[download.key]?.isDownloading = false
        modelData.activeDownloads[download.key]?.progress = 0.0
        modelData.activeDownloads[download.key]?.resumeData = nil
    }
    
    func pauseDownload(_ book: CalibreBook, format: Format) {
        guard let download = modelData.activeDownloads.filter({
                    $1.isDownloading && $1.book.id == book.id && $1.format == format
        }).first else {
            return
        }
        
        download.value.downloadTask?.cancel(byProducingResumeData: { resumeData in
            DispatchQueue.main.async {
                modelData.activeDownloads[download.key]?.isDownloading = false
                //modelData.activeDownloads[download.key]?.progress = 0.0
                modelData.activeDownloads[download.key]?.resumeData = resumeData
            }
        })
    }
    
    func resumeDownload(_ book: CalibreBook, format: Format) -> Bool {
        guard let bookFormatDownloadIndex = modelData.activeDownloads.firstIndex (where: {
                $1.book.id == book.id && $1.format == format && $1.resumeData != nil
        }) else {
            return false
        }
        let bookFormatDownload = modelData.activeDownloads[bookFormatDownloadIndex].value
        
        guard let resumeData = bookFormatDownload.resumeData else {
            return false
        }
        
        let downloadDelegate = BookFormatDownloadDelegate(download: modelData.activeDownloads[bookFormatDownloadIndex].value)
        
        let downloadConfiguration = URLSessionConfiguration.ephemeral
        downloadConfiguration.urlCredentialStorage = .shared

        let downloadSession = URLSession(configuration: downloadConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        let downloadTask = downloadSession.downloadTask(withResumeData: resumeData)
        
        if let credential = bookFormatDownload.credential, let protectionSpace = bookFormatDownload.protectionSpace {
            URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: downloadTask)
        }
        
        modelData.activeDownloads[bookFormatDownload.sourceURL]?.isDownloading = true
        modelData.activeDownloads[bookFormatDownload.sourceURL]?.resumeData = nil
        modelData.activeDownloads[bookFormatDownload.sourceURL]?.downloadTask = downloadTask
                
        downloadTask.resume()
        
        return true
    }
    
    func startDownload(_ book: CalibreBook, format: Format, overwrite: Bool = false) -> Bool {
        guard let formatInfo = book.formats[format.rawValue] else {
            return false
        }
        
        guard let url = URL(string: book.library.server.serverUrl)?
                .appendingPathComponent("get", isDirectory: true)
                .appendingPathComponent(format.rawValue, isDirectory: true)
                .appendingPathComponent(book.id.description, isDirectory: true)
                .appendingPathComponent(book.library.key, isDirectory: false)
                else {
            return false
        }

        defaultLog.info("downloadURL: \(url.absoluteString)")
        
        guard let savedURL = getSavedUrl(book: book, format: format) else {
            return false
        }
        
        self.defaultLog.info("savedURL: \(savedURL.absoluteString)")
        
        if FileManager.default.fileExists(atPath: savedURL.path) && !overwrite {
            return false
        }
        
        var bookFormatDownload = BookFormatDownload(book: book, format: format, sourceURL: url, savedURL: savedURL, modificationDate: formatInfo.serverMTime, downloadService: self)
        
        let downloadDelegate = BookFormatDownloadDelegate(download: bookFormatDownload)
        
        let downloadConfiguration = URLSessionConfiguration.ephemeral
        downloadConfiguration.urlCredentialStorage = .shared

        let downloadSession = URLSession(configuration: downloadConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        
        let downloadTask = downloadSession.downloadTask(with: url)
        
        if book.library.server.username.count > 0 && book.library.server.password.count > 0 {
            var authMethod = NSURLAuthenticationMethodDefault
            if url.scheme == "http" {
                authMethod = NSURLAuthenticationMethodHTTPDigest
            }
            if url.scheme == "https" {
                authMethod = NSURLAuthenticationMethodHTTPBasic
            }
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            if let credentials = URLCredentialStorage.shared.credentials(for: protectionSpace) {
                if let credential = credentials.filter({ $0.key == book.library.server.username }).first?.value {
                    bookFormatDownload.credential = credential
                    bookFormatDownload.protectionSpace = protectionSpace
                    URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: downloadTask)
                }
            }
        }
        
        bookFormatDownload.isDownloading = true
        bookFormatDownload.downloadTask = downloadTask
        
        modelData.activeDownloads[url] = bookFormatDownload
        
        downloadTask.resume()
        
        return true
    }
    
}

struct BookFormatDownload {
    var isDownloading = false
    var progress: Float = 0
    var resumeData: Data?
    var book: CalibreBook
    var format: Format
    
    var sourceURL: URL
    var savedURL: URL
    var modificationDate: Date
    
    var downloadService: BookFormatDownloadService?
    var downloadTask: URLSessionDownloadTask?
    var credential: URLCredential?
    var protectionSpace: URLProtectionSpace?
}

class BookFormatDownloadDelegate: NSObject, URLSessionDelegate, URLSessionDownloadDelegate {
    private var defaultLog = Logger()

    var download: BookFormatDownload
    
    var isFileExist = false
    
    init(download: BookFormatDownload) {
        self.download = download
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.defaultLog.info("fileURL: \(location.absoluteString)")
        
        do {
           //check size
            let fileAttribs = try FileManager.default.attributesOfItem(atPath: location.path)
            guard let fileSize = fileAttribs[.size] as? NSNumber, fileSize.uint64Value > 0 else {
                throw DownloadError(msg: "Empty file")
            }
            
            if FileManager.default.fileExists(atPath: download.savedURL.path) {
                try FileManager.default.removeItem(at: download.savedURL)
            }
            try FileManager.default.moveItem(at: location, to: download.savedURL)
            let attributes = [FileAttributeKey.modificationDate: download.modificationDate]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: download.savedURL.path)
            
            isFileExist = FileManager.default.fileExists(atPath: download.savedURL.path)
            self.defaultLog.info("isFileExist: \(self.isFileExist)")
            
        } catch {
            print ("file error: \(error)")
        }
        
        DispatchQueue.main.sync {
            download.downloadService?.modelData.activeDownloads[download.sourceURL]?.isDownloading = false
            download.downloadService?.modelData.activeDownloads[download.sourceURL]?.resumeData = nil
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let response = task.response,
           let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode),
           isFileExist {
            DispatchQueue.main.async { [self] in
                
                guard let modelData = download.downloadService?.modelData
                       else { return }
                
                modelData.addedCache(book: download.book, format: download.format)
                
            }
            
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        print("BookFormatDownloadDelegate.urlSession \(bytesWritten) \(totalBytesWritten) \(totalBytesExpectedToWrite)")
        guard let modelData = download.downloadService?.modelData else { return }
        
        DispatchQueue.main.async {
            modelData.activeDownloads[self.download.sourceURL]?.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
            print("BookFormatDownloadDelegate.urlSession \(bytesWritten) \(totalBytesWritten) \(totalBytesExpectedToWrite) \(modelData.activeDownloads[self.download.sourceURL]?.progress)")

        }
    }
    
}

struct DownloadError: Error {
    let msg: String
}
