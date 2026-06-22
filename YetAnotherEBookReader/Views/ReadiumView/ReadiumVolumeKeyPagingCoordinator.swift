//
//  ReadiumVolumeKeyPagingCoordinator.swift
//  YetAnotherEBookReader
//

import UIKit

public struct ReadiumVolumeKeyEventResolver {
    public enum Resolution: Equatable {
        case ignoreProgrammatic
        case ignoreBusy
        case pageUp
        case pageDown
    }
    
    public static func resolve(
        newVolume: Float,
        oldVolume: Float,
        lastRequestedVolume: Float?,
        isBusy: Bool
    ) -> Resolution {
        if let lastReq = lastRequestedVolume, abs(newVolume - lastReq) < 0.01 {
            return .ignoreProgrammatic
        }
        
        if isBusy {
            return .ignoreBusy
        }
        
        let isUp: Bool
        if let lastReq = lastRequestedVolume, abs(newVolume - oldVolume) > 0.15 {
            isUp = newVolume > lastReq
        } else {
            isUp = newVolume > oldVolume
        }
        
        return isUp ? .pageUp : .pageDown
    }
}

/// `ReadiumVolumeKeyPagingCoordinator` coordinates volume-key paging events.
/// It uses a layout-driven and completion-based async boundary instead of wall-clock timers
/// to avoid race conditions, double triggers, or missed events caused by arbitrary delays.
public class ReadiumVolumeKeyPagingCoordinator {
    public private(set) var isBusy = false
    public private(set) var lastRequestedVolume: Float?
    
    public init() {}
    
    public func handleVolumeChange(newVolume: Float, oldVolume: Float) -> ReadiumVolumeKeyEventResolver.Resolution {
        let resolution = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: newVolume,
            oldVolume: oldVolume,
            lastRequestedVolume: lastRequestedVolume,
            isBusy: isBusy
        )
        
        switch resolution {
        case .ignoreProgrammatic, .ignoreBusy:
            lastRequestedVolume = nil
        case .pageUp, .pageDown:
            lastRequestedVolume = nil
            isBusy = true
        }
        
        return resolution
    }
    
    public func requestVolumeChange(to volume: Float) {
        lastRequestedVolume = volume
    }
    
    public func unlock() {
        isBusy = false
    }
    
    public func reset() {
        isBusy = false
        lastRequestedVolume = nil
    }
    
    public static func findVolumeSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        for subview in view.subviews {
            if let found = findVolumeSlider(in: subview) { return found }
        }
        return nil
    }
}
