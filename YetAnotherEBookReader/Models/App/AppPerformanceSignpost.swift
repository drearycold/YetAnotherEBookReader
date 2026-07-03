//
//  AppPerformanceSignpost.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-27.
//

import Foundation
import OSLog

@available(iOS 15.0, macOS 12.0, *)
struct AppPerformanceSignpost {
    static let log = OSLog(subsystem: "com.drearycold.YetAnotherEBookReader", category: "PointsOfInterest")
    static let signposter = OSSignposter(logHandle: log)
    
    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        return signposter.beginInterval(name)
    }
    
    static func begin(_ name: StaticString, _ message: String) -> OSSignpostIntervalState {
        return signposter.beginInterval(name, "\(message)")
    }
    
    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
    
    static func end(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: String) {
        signposter.endInterval(name, state, "\(message)")
    }
    
    static func emit(_ name: StaticString) {
        signposter.emitEvent(name)
    }
    
    static func emit(_ name: StaticString, _ message: String) {
        signposter.emitEvent(name, "\(message)")
    }
}
