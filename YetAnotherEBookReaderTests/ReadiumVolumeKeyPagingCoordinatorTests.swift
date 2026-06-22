//
//  ReadiumVolumeKeyPagingCoordinatorTests.swift
//  YetAnotherEBookReaderTests
//

import XCTest
@testable import YetAnotherEBookReader

final class ReadiumVolumeKeyPagingCoordinatorTests: XCTestCase {
    
    func testResolverDirectionNormal() {
        // Normal User Event - Up
        let resUp = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: 0.5625,
            oldVolume: 0.5,
            lastRequestedVolume: nil,
            isBusy: false
        )
        XCTAssertEqual(resUp, .pageUp)
        
        // Normal User Event - Down
        let resDown = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: 0.4375,
            oldVolume: 0.5,
            lastRequestedVolume: nil,
            isBusy: false
        )
        XCTAssertEqual(resDown, .pageDown)
    }
    
    func testResolverProgrammaticMatch() {
        // Programmatic Event - exact match
        let res1 = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: 0.5,
            oldVolume: 0.4375,
            lastRequestedVolume: 0.5,
            isBusy: false
        )
        XCTAssertEqual(res1, .ignoreProgrammatic)
        
        // Programmatic Event - close enough match
        let res2 = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: 0.505,
            oldVolume: 0.4375,
            lastRequestedVolume: 0.5,
            isBusy: false
        )
        XCTAssertEqual(res2, .ignoreProgrammatic)
    }
    
    func testResolverBusySuppression() {
        // Event when busy
        let res = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: 0.5625,
            oldVolume: 0.5,
            lastRequestedVolume: nil,
            isBusy: true
        )
        XCTAssertEqual(res, .ignoreBusy)
    }
    
    func testResolverMassiveJump() {
        // Massive jump with pending requested volume
        // Target: 0.5, Old: 0.3, New: 0.45 -> Fell short of target 0.5 -> DOWN
        // Target: 0.5, Old: 0.2, New: 0.45 -> Fell short of target 0.5 -> DOWN
        let resDown = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: 0.45,
            oldVolume: 0.2,
            lastRequestedVolume: 0.5,
            isBusy: false
        )
        XCTAssertEqual(resDown, .pageDown)
        
        // Target: 0.5, Old: 0.8, New: 0.55 -> Overshot target 0.5 -> UP
        let resUp = ReadiumVolumeKeyEventResolver.resolve(
            newVolume: 0.55,
            oldVolume: 0.8,
            lastRequestedVolume: 0.5,
            isBusy: false
        )
        XCTAssertEqual(resUp, .pageUp)
    }
    
    func testCoordinatorLifecycle() {
        let coordinator = ReadiumVolumeKeyPagingCoordinator()
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertNil(coordinator.lastRequestedVolume)
        
        // 1. Programmatic requested volume set
        coordinator.requestVolumeChange(to: 0.5)
        XCTAssertEqual(coordinator.lastRequestedVolume, 0.5)
        
        // 2. Programmatic change triggers and is resolved
        let res1 = coordinator.handleVolumeChange(newVolume: 0.5, oldVolume: 0.4)
        XCTAssertEqual(res1, .ignoreProgrammatic)
        XCTAssertNil(coordinator.lastRequestedVolume) // cleared
        XCTAssertFalse(coordinator.isBusy)
        
        // 3. User page event triggers
        let res2 = coordinator.handleVolumeChange(newVolume: 0.5625, oldVolume: 0.5)
        XCTAssertEqual(res2, .pageUp)
        XCTAssertNil(coordinator.lastRequestedVolume)
        XCTAssertTrue(coordinator.isBusy) // now busy
        
        // 4. While busy, next user event is ignored
        let res3 = coordinator.handleVolumeChange(newVolume: 0.625, oldVolume: 0.5625)
        XCTAssertEqual(res3, .ignoreBusy)
        XCTAssertNil(coordinator.lastRequestedVolume)
        XCTAssertTrue(coordinator.isBusy)
        
        // 5. Unlock enables events again
        coordinator.unlock()
        XCTAssertFalse(coordinator.isBusy)
        
        let res4 = coordinator.handleVolumeChange(newVolume: 0.5, oldVolume: 0.5625)
        XCTAssertEqual(res4, .pageDown)
        XCTAssertTrue(coordinator.isBusy)
        
        // 6. Reset clears all state
        coordinator.reset()
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertNil(coordinator.lastRequestedVolume)
    }
    
    func testFindVolumeSlider() {
        let parentView = UIView()
        XCTAssertNil(ReadiumVolumeKeyPagingCoordinator.findVolumeSlider(in: parentView))
        
        let childView1 = UIView()
        let childView2 = UIView()
        parentView.addSubview(childView1)
        parentView.addSubview(childView2)
        
        XCTAssertNil(ReadiumVolumeKeyPagingCoordinator.findVolumeSlider(in: parentView))
        
        let slider = UISlider()
        childView2.addSubview(slider)
        
        let foundSlider = ReadiumVolumeKeyPagingCoordinator.findVolumeSlider(in: parentView)
        XCTAssertNotNil(foundSlider)
        XCTAssertEqual(foundSlider, slider)
    }
}
