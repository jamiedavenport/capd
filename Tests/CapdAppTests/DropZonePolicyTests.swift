import CoreGraphics
import Testing

@testable import CapdApp
@testable import CapdAppUI

@Suite("DropZonePolicy")
struct DropZonePolicyTests {
    private let notch = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchWidth: 200,
        notchHeight: 32)

    @Test("A drag in front of the notch draws the offer")
    func offersUnderNotch() {
        #expect(DropZonePolicy.offers(mouse: CGPoint(x: 756, y: 950), notch: notch))
    }

    @Test("The cursor pinned to the top edge still counts")
    func offersAtTopEdge() {
        #expect(DropZonePolicy.offers(mouse: CGPoint(x: 756, y: 982), notch: notch))
    }

    @Test("A drag below the approach depth stays quiet")
    func tooLow() {
        #expect(!DropZonePolicy.offers(mouse: CGPoint(x: 756, y: 870), notch: notch))
    }

    @Test("A drag toward the menu bar's far corners stays quiet")
    func tooFarSideways() {
        #expect(!DropZonePolicy.offers(mouse: CGPoint(x: 400, y: 970), notch: notch))
        #expect(!DropZonePolicy.offers(mouse: CGPoint(x: 1300, y: 970), notch: notch))
    }

    @Test("The zone follows a screen that doesn't sit at the origin")
    func offsetScreen() {
        let secondary = NotchGeometry(
            screenFrame: CGRect(x: 2000, y: 200, width: 1512, height: 982),
            notchWidth: 200,
            notchHeight: 32)

        #expect(DropZonePolicy.offers(mouse: CGPoint(x: 2756, y: 1150), notch: secondary))
        #expect(!DropZonePolicy.offers(mouse: CGPoint(x: 756, y: 950), notch: secondary))
    }

    @Test("Skimming the offered bar's edge keeps the offer")
    func barGraceBand() {
        let barFrame = CGRect(x: 556, y: 944, width: 400, height: 38)

        #expect(
            !DropZonePolicy.withdraws(
                mouse: CGPoint(x: 540, y: 950), notch: notch, barFrame: barFrame))
    }

    @Test("Wandering far from zone and bar withdraws the offer")
    func withdrawsWhenFar() {
        let barFrame = CGRect(x: 556, y: 944, width: 400, height: 38)

        #expect(
            DropZonePolicy.withdraws(
                mouse: CGPoint(x: 756, y: 500), notch: notch, barFrame: barFrame))
        #expect(
            DropZonePolicy.withdraws(
                mouse: CGPoint(x: 100, y: 970), notch: notch, barFrame: barFrame))
    }
}
