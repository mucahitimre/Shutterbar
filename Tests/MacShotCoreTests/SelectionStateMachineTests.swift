import CoreGraphics
import MacShotCore
import Testing

struct SelectionStateMachineTests {
    let bounds = CGSize(width: 1000, height: 800)

    func machine(quick: Bool = true, scale: CGFloat = 2, preview: CGRect? = nil) -> SelectionStateMachine {
        SelectionStateMachine(bounds: bounds, pixelScale: scale, quickCapture: quick, preview: preview)
    }

    @Test func quickCaptureCapturesOnMouseUp() {
        var sm = machine()
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        sm.mouseDragged(to: CGPoint(x: 60, y: 40))
        #expect(sm.mouseUp(at: CGPoint(x: 110, y: 60)) == .capture(CGRect(x: 10, y: 10, width: 100, height: 50)))
    }

    @Test func tinyDragIsIgnoredAsClick() {
        var sm = machine()
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        #expect(sm.mouseUp(at: CGPoint(x: 12, y: 50)) == .none)
        #expect(sm.selection == nil)
    }

    @Test func shiftMakesSquare() {
        var sm = machine()
        _ = sm.mouseDown(at: CGPoint(x: 100, y: 100))
        sm.mouseDragged(to: CGPoint(x: 300, y: 150), modifiers: .shift)
        #expect(sm.selection == CGRect(x: 100, y: 100, width: 50, height: 50))
        sm.modifiersChanged([])
        #expect(sm.selection == CGRect(x: 100, y: 100, width: 200, height: 50))
    }

    @Test func moveModifierTranslatesWhileDrawing() {
        var sm = machine()
        _ = sm.mouseDown(at: CGPoint(x: 100, y: 100))
        sm.mouseDragged(to: CGPoint(x: 200, y: 200))
        sm.mouseDragged(to: CGPoint(x: 250, y: 210), modifiers: .move)
        #expect(sm.selection == CGRect(x: 150, y: 110, width: 100, height: 100))
    }

    @Test func nonQuickRequiresEnter() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        #expect(sm.mouseUp(at: CGPoint(x: 110, y: 110)) == .none)
        #expect(sm.key(.enter) == .capture(CGRect(x: 10, y: 10, width: 100, height: 100)))
    }

    @Test func nonQuickDoubleClickInsideCaptures() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = sm.mouseUp(at: CGPoint(x: 110, y: 110))
        #expect(sm.mouseDown(at: CGPoint(x: 50, y: 50), clickCount: 2) == .capture(CGRect(x: 10, y: 10, width: 100, height: 100)))
    }

    @Test func nonQuickMoveSelection() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = sm.mouseUp(at: CGPoint(x: 110, y: 110))
        _ = sm.mouseDown(at: CGPoint(x: 50, y: 50))
        sm.mouseDragged(to: CGPoint(x: 70, y: 80))
        _ = sm.mouseUp(at: CGPoint(x: 70, y: 80))
        #expect(sm.selection == CGRect(x: 30, y: 40, width: 100, height: 100))
    }

    @Test func nonQuickResizeFromHandle() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = sm.mouseUp(at: CGPoint(x: 110, y: 110))
        _ = sm.mouseDown(at: CGPoint(x: 110, y: 110)) // bottomRight
        sm.mouseDragged(to: CGPoint(x: 210, y: 160))
        _ = sm.mouseUp(at: CGPoint(x: 210, y: 160))
        #expect(sm.selection == CGRect(x: 10, y: 10, width: 200, height: 150))

        _ = sm.mouseDown(at: CGPoint(x: 10, y: 85)) // left
        _ = sm.mouseUp(at: CGPoint(x: 300, y: 85)) // sol kenar sağ kenarı geçer → rect ters döner
        #expect(sm.selection == CGRect(x: 210, y: 10, width: 90, height: 150))
    }

    @Test func clickOutsideClearsInNonQuick() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = sm.mouseUp(at: CGPoint(x: 110, y: 110))
        _ = sm.mouseDown(at: CGPoint(x: 500, y: 500))
        _ = sm.mouseUp(at: CGPoint(x: 500, y: 500))
        #expect(sm.selection == nil)
    }

    @Test func escapeAndRightClickCancel() {
        var sm = machine()
        #expect(sm.key(.escape) == .cancel)
        #expect(sm.rightMouseDown() == .cancel)
    }

    @Test func deleteClearsSelection() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = sm.mouseUp(at: CGPoint(x: 110, y: 110))
        #expect(sm.key(.delete) == .none)
        #expect(sm.selection == nil)
        #expect(sm.key(.enter) == .none)
    }

    @Test func arrowMovesCursorByPixels() {
        var sm = machine(scale: 2)
        sm.mouseMoved(to: CGPoint(x: 100, y: 100))
        #expect(sm.key(.arrow(dx: 1, dy: 0)) == .warpCursor(CGPoint(x: 100.5, y: 100)))
        #expect(sm.key(.arrow(dx: 0, dy: -1), modifiers: .shift) == .warpCursor(CGPoint(x: 100.5, y: 95)))
    }

    @Test func arrowMovesSelectionWhenIdle() {
        var sm = machine(quick: false, scale: 1)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = sm.mouseUp(at: CGPoint(x: 110, y: 110))
        _ = sm.key(.arrow(dx: 1, dy: 0), modifiers: .shift)
        #expect(sm.selection == CGRect(x: 20, y: 10, width: 100, height: 100))
    }

    @Test func arrowWhileDrawingExtendsSelection() {
        var sm = machine(scale: 1)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        sm.mouseDragged(to: CGPoint(x: 50, y: 50))
        _ = sm.key(.arrow(dx: 1, dy: 1), modifiers: .shift)
        #expect(sm.selection == CGRect(x: 10, y: 10, width: 50, height: 50))
    }

    @Test func spaceAndTildeOutputs() {
        var sm = machine()
        #expect(sm.key(.space) == .captureAllScreens)
        #expect(sm.key(.activeScreen) == .captureActiveScreen)
    }

    @Test func previewAcceptedWithEnterInQuickMode() {
        let last = CGRect(x: 5, y: 5, width: 50, height: 50)
        var sm = machine(preview: last)
        #expect(sm.preview == last)
        #expect(sm.key(.enter) == .capture(last))
    }

    @Test func newDragInvalidatesPreview() {
        var sm = machine(preview: CGRect(x: 5, y: 5, width: 50, height: 50))
        _ = sm.mouseDown(at: CGPoint(x: 300, y: 300))
        sm.mouseDragged(to: CGPoint(x: 400, y: 400))
        #expect(sm.preview == nil)
    }

    @Test func previewBecomesEditableSelectionWhenNotQuick() {
        let last = CGRect(x: 5, y: 5, width: 50, height: 50)
        let sm = machine(quick: false, preview: last)
        #expect(sm.selection == last)
        #expect(sm.preview == nil)
    }

    @Test func outOfBoundsPreviewIsDropped() {
        let sm = machine(preview: CGRect(x: 900, y: 700, width: 200, height: 200))
        #expect(sm.preview == nil)
    }

    @Test func nonQuickKeepsSelectionUntilEnter() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        #expect(sm.mouseUp(at: CGPoint(x: 110, y: 110)) == .none)
        #expect(sm.selection == CGRect(x: 10, y: 10, width: 100, height: 100))
        _ = sm.key(.arrow(dx: 1, dy: 0))
        #expect(sm.key(.enter) == .capture(CGRect(x: 10.5, y: 10, width: 100, height: 100)))
    }

    @Test func copyKeyCopiesSelection() {
        var sm = machine(quick: false)
        #expect(sm.key(.copy) == .none)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = sm.mouseUp(at: CGPoint(x: 110, y: 110))
        #expect(sm.key(.copy) == .copy(CGRect(x: 10, y: 10, width: 100, height: 100)))
    }

    @Test func copyIgnoredWhileDrawing() {
        var sm = machine(quick: false)
        _ = sm.mouseDown(at: CGPoint(x: 10, y: 10))
        sm.mouseDragged(to: CGPoint(x: 50, y: 50))
        #expect(sm.key(.copy) == .none)
    }

    @Test func copyAcceptsPreview() {
        let last = CGRect(x: 5, y: 5, width: 50, height: 50)
        var sm = machine(preview: last)
        #expect(sm.key(.copy) == .copy(last))
    }

    @Test func digitSelectsScreen() {
        var sm = machine()
        #expect(sm.key(.screen(0)) == .captureScreen(0))
        #expect(sm.key(.screen(9)) == .captureScreen(9))
        #expect(sm.key(.screen(-1)) == .none)
    }
}
