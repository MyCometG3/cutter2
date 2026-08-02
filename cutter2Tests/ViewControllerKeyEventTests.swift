//
//  ViewControllerKeyEventTests.swift
//  cutter2Tests
//

import XCTest
import AVFoundation
@testable import cutter2

@MainActor
private final class MockViewControllerDelegate: ViewControllerDelegate {
    var setRateCalls: [Int] = []
    var setSlowCalls: [Float] = []
    var togglePlayCalls = 0
    var stepByCountCalls: [(count: Int64, resetStart: Bool, resetEnd: Bool)] = []
    var stepBySecondCalls: [(offset: Float64, resetStart: Bool, resetEnd: Bool)] = []
    var setStartCalls: [anchor] = []
    var setEndCalls: [anchor] = []
    var setCurrentCalls: [anchor] = []
    
    func hasSelection() -> Bool { false }
    func hasDuration() -> Bool { false }
    func hasClipOnPBoard() -> Bool { false }
    func debugInfo() {}
    func timeOfPosition(_ percentage: Float64) -> CMTime { .zero }
    func positionOfTime(_ time: CMTime) -> Float64 { 0.0 }
    func doCut() throws {}
    func doCopy() throws {}
    func doPaste() throws {}
    func doDelete() throws {}
    func selectAll() {}
    
    func doStepByCount(_ count: Int64, _ resetStart: Bool, _ resetEnd: Bool) {
        stepByCountCalls.append((count, resetStart, resetEnd))
    }
    
    func doStepBySecond(_ offset: Float64, _ resetStart: Bool, _ resetEnd: Bool) {
        stepBySecondCalls.append((offset, resetStart, resetEnd))
    }
    
    func doVolumeOffset(_ percent: Int) {}
    func doMoveLeft(_ optFlag: Bool, _ shiftFlag: Bool, _ resetStart: Bool, _ resetEnd: Bool) {}
    func doMoveRight(_ optFlag: Bool, _ shiftFlag: Bool, _ resetStart: Bool, _ resetEnd: Bool) {}
    
    func doSetSlow(_ ratio: Float) {
        setSlowCalls.append(ratio)
    }
    
    func doSetRate(_ offset: Int) {
        setRateCalls.append(offset)
    }
    
    func doTogglePlay() {
        togglePlayCalls += 1
    }
    
    func didUpdateCursor(to position: Float64) {}
    func didUpdateStart(to position: Float64) {}
    func didUpdateEnd(to position: Float64) {}
    func didUpdateSelection(from fromPos: Float64, to toPos: Float64) {}
    func presentationInfo(at position: Float64) -> PresentationInfo? { nil }
    func previousInfo(of range: CMTimeRange) -> PresentationInfo? { nil }
    func nextInfo(of range: CMTimeRange) -> PresentationInfo? { nil }
    
    func doSetCurrent(to goTo: anchor) {
        setCurrentCalls.append(goTo)
    }
    
    func doSetStart(to goTo: anchor) {
        setStartCalls.append(goTo)
    }
    
    func doSetEnd(to goTo: anchor) {
        setEndCalls.append(goTo)
    }
}

@MainActor
final class ViewControllerKeyEventTests: XCTestCase {
    private var viewController: ViewController!
    private var mockDelegate: MockViewControllerDelegate!
    
    override func setUp() async throws {
        try await super.setUp()
        viewController = ViewController(nibName: nil, bundle: nil)
        mockDelegate = MockViewControllerDelegate()
        viewController.delegate = mockDelegate
    }
    
    override func tearDown() async throws {
        viewController = nil
        mockDelegate = nil
        try await super.tearDown()
    }
    
    private func event(
        type: NSEvent.EventType = .keyDown,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0.0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
    
    func testJKLMode_J_NoModifier_CallsSetRate() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x26, characters: "j"))
        
        XCTAssertEqual(mockDelegate.setRateCalls, [-1])
    }
    
    func testJKLMode_K_NoModifier_CallsSetRate() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x28, characters: "k"))
        
        XCTAssertEqual(mockDelegate.setRateCalls, [0])
    }
    
    func testJKLMode_L_NoModifier_CallsSetRate() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x25, characters: "l"))
        
        XCTAssertEqual(mockDelegate.setRateCalls, [1])
    }
    
    func testJKLMode_Space_NoModifier_CallsTogglePlay() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x31, characters: " "))
        
        XCTAssertEqual(mockDelegate.togglePlayCalls, 1)
    }
    
    func testJKLMode_JK_Combo_CallsSetSlow() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x26, characters: "j"))
        viewController.keyDown(with: event(keyCode: 0x28, characters: "k"))
        
        XCTAssertEqual(mockDelegate.setSlowCalls, [-0.5])
    }
    
    func testJKLMode_LK_Combo_CallsSetSlow() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x25, characters: "l"))
        viewController.keyDown(with: event(keyCode: 0x28, characters: "k"))
        
        XCTAssertEqual(mockDelegate.setSlowCalls, [0.5])
    }
    
    func testJKLMode_KeyUpK_AfterJK_CallsSetRate() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x26, characters: "j"))
        viewController.keyDown(with: event(keyCode: 0x28, characters: "k"))
        viewController.keyUp(with: event(type: .keyUp, keyCode: 0x28, characters: ""))
        
        XCTAssertEqual(mockDelegate.setRateCalls, [-1, -1])
    }
    
    func testJKLMode_J_WithOptionShift_AfterJK_CallsStepBySecond() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x26, characters: "j"))
        viewController.keyDown(with: event(keyCode: 0x28, characters: "k"))
        viewController.keyDown(with: event(
            keyCode: 0x26,
            modifiers: [.option, .shift],
            characters: "j"
        ))
        
        XCTAssertEqual(mockDelegate.stepBySecondCalls.count, 1)
        XCTAssertEqual(mockDelegate.stepBySecondCalls[0].offset, -viewController.offsetM, accuracy: 0.001)
        XCTAssertFalse(mockDelegate.stepBySecondCalls[0].resetStart)
        XCTAssertFalse(mockDelegate.stepBySecondCalls[0].resetEnd)
    }
    
    func testJKLMode_I_NoModifier_SetsStart() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x22, characters: "i"))
        
        XCTAssertEqual(mockDelegate.setStartCalls.count, 1)
        XCTAssertEqual(mockDelegate.setStartCalls[0], .current)
    }
    
    func testJKLMode_O_NoModifier_SetsEnd() {
        viewController.mimicJKLcombination = true
        viewController.keyDown(with: event(keyCode: 0x1f, characters: "o"))
        
        XCTAssertEqual(mockDelegate.setEndCalls.count, 1)
        XCTAssertEqual(mockDelegate.setEndCalls[0], .current)
    }
    
    func testStepMode_J_NoModifier_CallsStepBySecond() {
        viewController.mimicJKLcombination = false
        viewController.keyDown(with: event(keyCode: 0x26, characters: "j"))
        
        XCTAssertEqual(mockDelegate.stepBySecondCalls.count, 1)
        XCTAssertEqual(mockDelegate.stepBySecondCalls[0].offset, -viewController.offsetL, accuracy: 0.001)
    }
    
    func testStepMode_K_NoModifier_CallsStepBySecond() {
        viewController.mimicJKLcombination = false
        viewController.keyDown(with: event(keyCode: 0x28, characters: "k"))
        
        XCTAssertEqual(mockDelegate.stepBySecondCalls.count, 1)
        XCTAssertEqual(mockDelegate.stepBySecondCalls[0].offset, -viewController.offsetS, accuracy: 0.001)
    }
    
    func testStepMode_L_NoModifier_CallsStepBySecond() {
        viewController.mimicJKLcombination = false
        viewController.keyDown(with: event(keyCode: 0x25, characters: "l"))
        
        XCTAssertEqual(mockDelegate.stepBySecondCalls.count, 1)
        XCTAssertEqual(mockDelegate.stepBySecondCalls[0].offset, viewController.offsetS, accuracy: 0.001)
    }
    
    func testStepMode_Semicolon_NoModifier_CallsStepBySecond() {
        viewController.mimicJKLcombination = false
        viewController.keyDown(with: event(keyCode: 0x29, characters: ";"))
        
        XCTAssertEqual(mockDelegate.stepBySecondCalls.count, 1)
        XCTAssertEqual(mockDelegate.stepBySecondCalls[0].offset, viewController.offsetL, accuracy: 0.001)
    }
}
