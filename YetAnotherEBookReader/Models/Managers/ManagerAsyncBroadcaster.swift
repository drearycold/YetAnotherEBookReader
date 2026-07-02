//
//  ManagerAsyncBroadcaster.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026/07/02.
//

import Foundation

final class ManagerAsyncBroadcaster<Element> {
    private let lock = NSLock()
    private var continuations = [UUID: AsyncStream<Element>.Continuation]()

    func stream() -> AsyncStream<Element> {
        makeStream(initialValue: nil)
    }

    func stream(initialValue: Element) -> AsyncStream<Element> {
        makeStream(initialValue: initialValue)
    }

    private func makeStream(initialValue: Element?) -> AsyncStream<Element> {
        AsyncStream { [weak self] continuation in
            let id = UUID()
            if let initialValue {
                continuation.yield(initialValue)
            }
            self?.lock.lock()
            self?.continuations[id] = continuation
            self?.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    func send(_ value: Element) {
        lock.lock()
        let currentContinuations = continuations.map { $0.value }
        lock.unlock()
        for continuation in currentContinuations {
            continuation.yield(value)
        }
    }

    func finish() {
        lock.lock()
        let currentContinuations = continuations.map { $0.value }
        continuations.removeAll()
        lock.unlock()
        currentContinuations.forEach { $0.finish() }
    }
}
